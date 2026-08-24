#!/usr/bin/env bash
# ship-land.sh — the ENTIRE claude-infrastructure landing pipeline as ONE fail-closed script
# (was prose in .claude/commands/ship.md a model could skip or paraphrase).
#
#   scripts/ship-land.sh [--trunk <branch>] [--dry-run]
#   scripts/ship-land.sh --precheck [--working] [--trunk <branch>] [--fetch]   (P2 shift-left)
#
# --precheck is the SHIFT-LEFT entry point (land-architecture-100p §5 P2). It runs THE SAME
# run_gate() this script lands with — same function, same lints, same own-scope sets, same
# gate_red arms — against the same range, in the author's own worktree, taking NO lock, writing
# NO land.log row, touching NO ref, and reaching NO network unless asked. Exit 0 = the land gate
# would go green on this tree; 6 = it would go RED (and it names the arm); 9 = GATE-KILLED.
#   --working  gate the WORKING TREE (base..worktree, uncommitted edits included) instead of
#              base..HEAD — the true commit-time position, for use before/while committing.
#   --fetch    refresh origin/<trunk> first (default: offline, using the local ref).
# WHAT IT COVERS, stated plainly because the honest scope is the point: statics (shellcheck /
# `bash -n` / py_compile) AND all fifteen ratchet arms — which are ~112s of the land gate's
# 127-137s (§5.P3), i.e. the expensive part, not the cheap 2%. It does NOT run the bats smoke
# phase; smoke is already `none`/`skipped` on **84.8%** of the invocations that record the field
# (measured 2026-08-11 by scripts/gate-red-census.sh over 1,651 invocations — §2.B's "89%" is the
# same finding taken by hand, and the tool is now the citable source), so its absence here cannot
# move the red rate this entry point exists to pre-empt. A precheck-green tree can still be reddened
# at land time by smoke, or by a ratchet arm whose input a SIBLING's land changed between the two
# runs — precheck is a strictly EARLIER read of the same predicate, never a substitute verdict.
# IT CANNOT SHADOW THE LAND GATE: nothing in the land path reads any precheck output, and
# --precheck sets no state a land consults (see main_precheck, and tests/gate-precheck.bats,
# which asserts a red tree stays red at land time after a precheck of the same tree).
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
#         rolls back (rebase --abort) ⇒ exit 5, retries exhausted ⇒ clean tree + exit 8. Every
#         in-lock fetch/push is bounded by timeout(1); a bound firing is a MACHINE verdict
#         (exit 10, retryable), never a red — see git_net.
#       → THE LOCK RELEASES HERE, and the rest runs in the outer process, unlocked: backup-ref
#         reap → stranded-sweep (exit 1 ⇒ REVIEW, surfaced, never auto-recovered) → self-attesting
#         land.log line → post-land verifier kick. Both of those were INSIDE the mutex until
#         2026-08-10 and were ~90% of an 87s median hold, for work the lock does not protect;
#         see post_release_finish for why moving them out is sound rather than merely faster.
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
#   SHED = SKIP          at 1-min load ≥ CC_GATE_MAX_LOAD the smoke is SKIPPED ENTIRELY, never
#                        waited (R7). Waiting WAS the amplifier; shedding defers to the net, never
#                        to a queue. Fail-OPEN: an unreadable sensor runs the (bounded) smoke
#                        rather than inventing a skip. The DEFAULT ceiling is DERIVED — hw.ncpu ×
#                        CC_GATE_MAX_LOAD_PER_CORE (8), so 80 on a 10-core box — because the old
#                        constant 8 was 0.8/core here and shed 87% of all lands (352/405). It is
#                        a runaway circuit-breaker, NOT a capacity model; see load_above_ceiling.
#
# A land makes NO full-suite claim: GATE_EFFECTIVE_FULL is 0 always — in BOTH lanes — so
# stamp_gate_green self-noops and gate-green advances ONLY via the verifier (§4.2). Two writers
# for one marker is strictly worse than a stale one.
#
# --dry-run stops after the gate (no push, no lock). Exit codes: 0 landed · 2 preflight refusal ·
# 3 escalation PARK · 4 shared-checkout refusal · 5 rebase conflict (initial OR an auto-retry
# rebase, the latter rolled back) · 6 GATE RED · 7 push non-ff · 8 content-verify failed after
# exhausting the bounded auto-retries · 9 GATE-KILLED (now rare — only LANE=v1's corpus can earn
# it) · 10 IN-LOCK NET TIMEOUT (a fetch/push inside the mutex exceeded SHIP_LAND_NET_TIMEOUT_S —
# a MACHINE verdict like 9, retryable, nothing proven, tree clean) · 11 A LAND IS ALREADY IN
# FLIGHT for this worktree (P4 defect 3 — refused BEFORE the mutex, so a double-fire costs nothing)
# · 128+N a SIGNALLED death, attested (P4 defect 1). 42 is INTERNAL (locked child → outer-loop
# stale-gate signal); it never escapes ship-land.
#
# 6 vs 9 — a VERDICT vs a NON-VERDICT, and the distinction is load-bearing (backlog 9c5d0ba74e79):
# 6 says "the gate ran and this tree is red" — a claim about YOUR CODE, actionable, do not retry
# unchanged. 9 says the suite died to a signal (or exited naming no failing test) and therefore
# proved NOTHING — a claim about the MACHINE. Nothing is pushed either way and gate-green is never
# advanced, so 9 is still fail-closed; what changes is that a retry is the CORRECT response to 9
# and the wrong one to 6. Collapsing them into 6 is what let a load spike read as a code failure
# and drove the 2026-07-26 kill → "RED" → re-block → dispatcher-retry runaway (f8e40b4c577d).
#
# OWNERSHIP (decidable sweep, T-P9-4) — CORRECTED 2026-08-12, this used to describe a convention
# that was never built. It read: "a session's commits should carry a `Session-Id:
# <CLAUDE_CODE_SESSION_ID>` trailer ... and [ship-land] adds the trailer to any commit IT makes."
# MEASURED: 0 of the last 500 commits on origin/main carry `Session-Id:` or `Land-Session:`, and
# nothing in this tree writes either. A comment asserting a convention is not a writer of one, and
# this paragraph was the entire evidence base for an attribution arm that could only ever report 0.
# What ship-land ACTUALLY writes, and what `stranded-sweep.sh --mine <sid>` now keys on, are two
# anchors that exist: a `refs/land/failed/<ts>-<sid>-<branch>` ref (the pinned head of a land that
# failed) and a land.log row's `head` for that sid (a land that succeeded). A stranded sha is ours
# iff an anchor reaches it. The trailer arm survives in the sweep as a dead-but-present last resort
# — it starts working the day something writes one — but nothing depends on it.
#
# land.log schema (growth is safe — the readers select by key): `gate_scope` carries the LANE
# ("fast"|"v1"), plus smoke, smoke_n, smoke_s, and net:"live|inert|none". The verifier's liveness is
# ATTESTED, never a control-flow input: a land that cannot see a live net WARNS and lands anyway —
# degrading to a corpus is precisely the fail-closed-amplifier class v2 exists to delete (R7).
#
# P0 (land-architecture-100p §5 P0) added the fields that let the pipeline answer questions about
# ITSELF, and every one of them exists because a question the acceptance criteria ASK was
# unanswerable from this store:
#   stage:"land"|"round"  a terminal outcome, or an internal stale-gate re-round. ABSENT ⇒ "land",
#                         which is what every pre-P0 row is and what every rate already assumed.
#   total_s               END-TO-END wall seconds. v2's "land latency p50 ≤ 30s" names this store
#                         and there was no duration in it; the criterion could not be checked.
#   gate_rounds · gate_s · gate_arms_s · gate_statics_s
#                         how many gates this land ran and where the seconds went. Split because
#                         §5.P3 measured the ratchet arms at ~112s of a 127-137s re-round — one
#                         opaque total cannot separate "re-gated three times" from "the remote hung".
#   smoke:"green|red|partial|skipped|none-<cause>"
#                         `none` was FIVE causes in one token (six, once the gate-died-first case is
#                         counted) over 83% of lands. See run_smoke for the enumeration.
# Every terminal exit now writes a row — exits 2/4/7/42 and the in-lock fallback's 6 wrote none, so
# a land could die in five ways that left the instrument reading "never attempted" (see
# _land_exit_trap). Census renderer: scripts/gate-red-census.sh.
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
# CC_GATE_MAX_LOAD (ABSOLUTE ceiling; 0|off ⇒ never shed; UNSET ⇒ derived, see below) ·
# CC_GATE_MAX_LOAD_PER_CORE (default 8 — the derived default's factor) ·
# SHIP_LAND_SHARED_CHECKOUT · SHIP_LAND_SESSION_BRANCH_RE
# · SHIP_LAND_ALLOW_SHARED=1 · SHIP_LAND_ESC_RE (EFFECT class — exemptible) ·
# SHIP_LAND_ESC_RE_SECRET (DISCLOSURE class — never exemptible) · SHIP_LAND_ESC_EXEMPT_FILE
# (default scripts/esc-exempt.manifest) · SHIP_LAND_DECISIONS_DIR · LAND_LOG ·
# LAND_LOCK_DIR (see land-lock.sh) · SHIP_LAND_NET_TIMEOUT_S (default 60 — the bound on every
# IN-LOCK fetch/push; SHIP_LAND_TIMEOUT_BIN= disables bounding entirely) ·
# SHIP_LAND_VERIFY_RETRIES (default 2; 0 = single-shot,
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
# THE REFUSAL IS DEFERRED TO DISPATCH (validate_lane_scope, called from the dispatch block at the
# foot of this file) — the VALUE is still bound here, where every function below expects it. It used
# to `exit 2` inline, at a line that runs before the traps are installed and before attest_land is
# even defined, so the one exit code an operator can trigger by typo was structurally incapable of
# attesting (P0 §2.B). Deferring the check costs nothing: nothing between here and dispatch acts on
# the value, and both entry points validate before doing any work.

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
# Deferred to validate_lane_scope for the same reason as LANE above — the refusal is unchanged in
# effect (same message, same exit 2, before any work), it just now happens where it can attest.
validate_lane_scope() {
  case "$LANE" in
    fast|v1) ;;
    *) echo "✗ ship-land: unknown SHIP_LAND_LANE '$LANE' (want fast|v1)" >&2; exit 2 ;;
  esac
  case "$SCOPE" in
    full|scoped|shadow) ;;
    *) echo "✗ ship-land: unknown SHIP_LAND_GATE_SCOPE '$SCOPE' (want full|scoped|shadow)" >&2; exit 2 ;;
  esac
}
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
GATE_RED_WHY=""   # WHICH arm(s) went red, fire-ordered "arm[:subject]" list — attested as "red"

# ATTRIBUTE THE RED (GATE_ARCHITECTURE_PLAN §9 item 4). land.log recorded `exit` and nothing else,
# so a red was a number: the plan's own post-mortem of a 44-red window had to INFER cause from an
# exit code and said so — "every post-mortem here is inference over an exit code, which is the same
# blindness §1 was written to escape". §9 then blocks further probabilistic modelling on this being
# fixed, because §1's `P=(1-q)^n` model cannot even SEE the deterministic blockers (ratchet,
# wall-clock bomb, deploy drift) that the same section measured as the real blocking class. You
# cannot tell those two populations apart in a corpus of bare 6s.
#
# gate_red() is the ONLY sanctioned way to raise GATE_RED — a bare assignment to it is a red that
# attests as "unattributed", and tests/ship-land.bats fails the build on one, so a NEW arm cannot
# silently re-open the blind spot. That ratchet is the point: 22 arms can raise a red here and the
# next one is written by someone who never read this comment. The lint is a whole-file count of the
# assignment literal, which is why this sentence spells the literal out in words rather than quoting
# it — a comment that quoted it would make the lint's own explanation into a violation.
gate_red() {  # $1=arm  [$2=subject: the file/suite it named] — raise GATE_RED *and* say why
  GATE_RED=1
  local why="$1"
  [[ -n "${2:-}" ]] && why="$1:$2"
  # `,` separates arms and `:` separates arm from subject, so neither may survive inside a subject;
  # everything outside the JSON-safe set goes too, because land.log is one JSON object per line and
  # a stray quote/backslash from a filename would corrupt the line for every reader on the box.
  why="$(printf '%s' "$why" | tr -c 'A-Za-z0-9._/:=-' '-' | tr -s '-')"
  # Already at the cap ⇒ stop appending. Without this the next arm would be concatenated and the
  # result re-truncated THROUGH the marker ("...+trunca+truncated"), i.e. the field would start
  # eating its own honesty token — the bound has to be sticky, not re-applied.
  case "$GATE_RED_WHY" in *'+truncated') return 0 ;; esac
  case ",${GATE_RED_WHY}," in *",${why},"*) return 0 ;; esac   # same arm twice ⇒ one entry
  GATE_RED_WHY="${GATE_RED_WHY:+${GATE_RED_WHY},}${why}"
  # Bounded, and LOUDLY: a truncation that reads as a complete list would be a fresh instance of the
  # blindness this whole field exists to remove, so the cut is named in the value itself. Reachable
  # in practice — the bats/smoke arms name every failing suite, not just the first.
  if (( ${#GATE_RED_WHY} > 240 )); then
    GATE_RED_WHY="${GATE_RED_WHY:0:240}+truncated"
  fi
  return 0
}

# ---- SMOKE + NET state (attested, seeded across the locked re-exec like SELECTED_N) ---------
# SMOKE_STATE is green | red | partial | skipped | none-<cause>. The bare `none` survives ONLY as
# the pre-P0 legacy value and as the value no code path claims — see the none-* block in run_smoke.
SMOKE_STATE="${SHIP_LAND_SMOKE_STATE:-none}"
SMOKE_N="${SHIP_LAND_SMOKE_N:-0}"              # direct suites the smoke actually RAN
SMOKE_S="${SHIP_LAND_SMOKE_S:-0}"              # wall seconds the smoke spent
NET_STATE="${SHIP_LAND_NET_STATE:-none}"       # live | inert | none — ATTESTED, never enforced
SMOKE_DEADLINE=""                              # non-empty ⇒ gate_bats bounds every child by it

# ---- P0: THE PIPELINE MEASURES ITSELF ---------------------------------------
# (land-architecture-100p-2026-08-10 §5 P0 / §2.B.) v2's own acceptance criterion — "land latency
# p50 ≤ 30s, p99 ≤ 3 min" — names land.log as the artifact to read it from, and land.log carried NO
# END-TO-END DURATION FIELD. The criterion was structurally unverifiable from the instrument it
# nominates, so the acceptance read was prose in both directions: the published hold figures
# (README "5-15s", ship.md "84-302s") contradicted each other AND the store, and neither could be
# refuted by anything cheaper than an investigation.
#
# THREE FIELDS, and the split is the point. `total_s` alone would be one opaque number over a
# pipeline whose cost is known to be concentrated: §5.P3 measured the fifteen ratchet arms at ~112s
# of a 127-137s re-round, so a land that is slow because it re-gated three times is a different
# animal from one that is slow because the remote hung, and a total cannot tell them apart.
#   total_s      wall seconds from the OUTER process's first line to this row. Survives the locked
#                re-exec via SHIP_LAND_T0, so it is end-to-end and not per-process.
#   gate_rounds  how many times run_gate ran for this land — the CAS re-round counter, made visible.
#   gate_s       cumulative wall seconds inside run_gate, of which:
#   gate_arms_s  the fifteen ratchet arms (the dominant term, per §5.P3), and
#   gate_statics_s  shellcheck / bash -n / py_compile (the ~2% the P3 memo already retired).
#
# COST INSIDE THE MUTEX: two date(1) forks per gate call and one per attest, all outside the lock
# except the attest itself — which already forked `date -u` before this existed. P1 spent a whole
# session emptying this mutex; an instrument that re-filled it would have destroyed its own subject.
LAND_T0="${SHIP_LAND_T0:-}"
[[ -z "$LAND_T0" ]] && LAND_T0="$(date +%s)"
MEAS_ROUNDS="${SHIP_LAND_MEAS_ROUNDS:-0}"
MEAS_GATE_S="${SHIP_LAND_MEAS_GATE_S:-0}"
MEAS_ARMS_S="${SHIP_LAND_MEAS_ARMS_S:-0}"
MEAS_STATICS_S="${SHIP_LAND_MEAS_STATICS_S:-0}"
GATE_T0=""              # non-empty ⇒ a gate is OPEN (run_gate was entered and has not closed)
GATE_T_STATICS_END=""   # set at the statics/arms boundary inside run_gate
GATE_T_ARMS_END=""      # set at the arms/smoke boundary inside run_gate

# ---- P0: the attest latch, and who is entitled to write a row ---------------
# ATTESTED is what makes "attest every terminal exit" expressible as ONE mechanism instead of a
# call bolted onto each of the fourteen `exit` sites: the EXIT trap attests whatever nobody else
# did, and this latch is how it knows. ATTEST_SUPPRESS is the other direction — a row that must
# NOT be written because someone else already wrote THIS outcome (the locked child) or because the
# invocation is not a land at all (the precheck, whose contract is that it writes no land.log row).
ATTESTED=0
ATTEST_SUPPRESS=0
# A --precheck invocation is suppressed from its FIRST line, not from main_precheck: the LANE/SCOPE
# refusals and main_outer's own arg-parse refusals fire before that function is reached, and a
# precheck that mistyped a flag must not mint a land.log row for a land that never started.
case " $* " in *' --precheck '*) ATTEST_SUPPRESS=1 ;; esac

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

# ---- R5 applied to the LOCK ITSELF: bounding the in-lock network ------------
# The mutex exists to cover the fetch→push→verify race window, so an UNBOUNDED net call inside it
# is the one failure that turns a sub-second hold into an indefinite machine-wide wedge. It is not
# hypothetical and it is not self-healing: land-lock NEVER reaps a live holder (its H2 rule, chosen
# deliberately — a silently-dropped commit costs more than a wedged wait), so a `git push` hung on
# an unresponsive remote stops EVERY lander on this box until a human notices. Every in-lock net op
# therefore runs under timeout(1).
#
# A TIMEOUT IS A MACHINE VERDICT (exit 10), never a gate red — the same split 6 vs 9 already draws
# for the gate, for the same reason: a bound firing is the ABSENCE of an answer from the remote, so
# it is evidence about the box and the network, not about the tree. Retrying is the correct response
# to 10 and the wrong response to 6. Ordinary non-zero keeps each call site's existing semantics —
# a timeout is not a failure, and collapsing them would recode a non-ff rejection (exit 7, "a
# sibling beat you") as "retry", which is how a load spike became a code failure in 2026-07-26.
# Kill switch: SHIP_LAND_TIMEOUT_BIN= (empty) ⇒ unbounded, the same seam the smoke already honors.
NET_TIMEOUT_S="${SHIP_LAND_NET_TIMEOUT_S:-60}"
NET_TIMED_OUT=0
git_net() {  # <git args…> → git's rc; sets NET_TIMED_OUT=1 IFF the bound fired
  NET_TIMED_OUT=0
  local rc
  if [[ -n "$TIMEOUT_BIN" && -x "$TIMEOUT_BIN" ]]; then
    "$TIMEOUT_BIN" -k 10 "$NET_TIMEOUT_S" git "$@"; rc=$?
    # timeout(1): 124 = the bound fired; 137 = the `-k` SIGKILL landed after it refused to die.
    [[ "$rc" -eq 124 || "$rc" -eq 137 ]] && NET_TIMED_OUT=1
  else
    git "$@"; rc=$?
  fi
  return "$rc"
}

net_timeout_abort() {  # $1=the op, as the operator would type it  $2=base for the attest  $3=note
  echo "⛔ ship-land: in-lock \`git $1\` exceeded ${NET_TIMEOUT_S}s and was killed — the remote never answered. That is a claim about the MACHINE and the network, NOT about your tree: nothing was proven, gate-green is untouched, the branch and the backup ref ship/backup-* are intact, and the tree is clean. $3 Re-run /ship (exit 10)." >&2
  attest_refs "$2"
  attest_land "n/a" "n/a" "clean" 10
  exit 10
}

# ---- WHY a push was refused: a RACE vs anything else (backlog a85dbba865f3) --
# A failed `git push` had exactly one spelling here — "non-fast-forward — a sibling beat you inside
# the window" — for EVERY non-timeout failure. A pre-push HOOK refusal (githooks/pre-push refusing a
# mis-authored range) is the common non-race case and was reported as a trunk race, which sends the
# reader chasing siblings that were never there. scripts/cloud-reconcile.sh:618,656 already had to
# work around exactly this ("ship-land would report that refusal as exit 7, an ordinary push race,
# which is why it is caught HERE").
#
# The needles are MEASURED, not inferred from our own wording (probe 2026-08-22, both arms in one
# script against a real bare remote):
#   * a genuine non-ff prints  `! [rejected]        HEAD -> main (fetch first)`  — and the literal
#     string "non-fast-forward" does NOT appear in it. Keying on the phrase our own error message
#     uses would read 0 on the very case it names, so the discriminator is the `! [rejected]` line
#     plus git's parenthesised reason, whose spellings are (fetch first)/(non-fast-forward)/(stale
#     info).
#   * a hook refusal prints NO rejected line at all — only `error: failed to push some refs`, with
#     the hook's own diagnostic ahead of it.
# So the two are cleanly separable from git's own output, and nothing else is needed: this asks only
# "did git say a ref was rejected for a fast-forward reason", never "did the trunk move", so it costs
# no extra in-lock network call.
#
# Counts, never `grep -q`: under this file's `set -o pipefail` a producer piped into an early-exiting
# `grep -q` reads FALSE **on a match** (the same trap already documented at the two grep sites below).
push_failure_kind() {  # $1 = git push's combined output → "non-ff" (a real race) | "refused"
  local out="${1-}" n_rejected n_ffreason
  n_rejected="$(printf '%s' "$out" | /usr/bin/grep -c '! \[rejected\]' || true)"
  n_ffreason="$(printf '%s' "$out" | /usr/bin/grep -cE '\((fetch first|non-fast-forward|stale info)\)' || true)"
  if [ "${n_rejected:-0}" -gt 0 ] && [ "${n_ffreason:-0}" -gt 0 ]; then
    echo "non-ff"
  else
    echo "refused"
  fi
}

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

gate_meas_close() {  # close an OPEN gate measurement — idempotent, and safe to call from anywhere
  # The fifteen ratchet arms `return 1` straight out of run_gate (fail-fast, deliberately), so the
  # arms and the whole-gate timers cannot be closed at the bottom of that function alone. They are
  # closed HERE instead, from run_gate's own tail on the green path and from attest_land on every
  # red — which is exact, because a gate red always attests before it exits. An unclosed gate is
  # therefore impossible to attest, rather than silently attesting 0.
  [[ -n "${GATE_T0:-}" ]] || return 0
  local now; now="$(date +%s)"
  local se="${GATE_T_STATICS_END:-$now}" ae="${GATE_T_ARMS_END:-}"
  # Died inside the arms ⇒ the arms ran until now. Died inside the statics ⇒ both boundaries are
  # `now`, so arms_s adds 0 and statics_s carries the whole span. Neither case invents a phase.
  [[ -z "$ae" ]] && ae="$now"
  MEAS_GATE_S=$(( MEAS_GATE_S + now - GATE_T0 ))
  MEAS_STATICS_S=$(( MEAS_STATICS_S + se - GATE_T0 ))
  MEAS_ARMS_S=$(( MEAS_ARMS_S + ae - se ))
  GATE_T0=""; GATE_T_STATICS_END=""; GATE_T_ARMS_END=""
  return 0
}

attest_land() {  # $1=verify $2=sweep $3=esc $4=exit [$5=stage: land|round] — self-attesting line
  # Schema GROWTH is safe: land.log's only reader is a raw tail. head/base/tree make a line
  # replayable (which tree was gated); gate_scope now carries the LANE, and smoke/smoke_n/smoke_s
  # + net make "what did this land actually prove, and was the net alive to prove the rest?"
  # answerable per land — the §7 acceptance read (p50/p99, zero exit-9) comes from exactly here.
  #
  # THE PRECHECK MAY NEVER REACH THIS (P2's contract: a precheck is not a land attempt, and counting
  # it as one poisons the denominator the census reports). Enforced here rather than at the call
  # sites, because P0 added a call site — the EXIT trap — that fires on paths nobody enumerated.
  [[ "${ATTEST_SUPPRESS:-0}" = "1" ]] && return 0
  gate_meas_close
  # REPO_ROOT / BRANCH are set by main_outer and main_locked, and the P0 trap attests from paths
  # that run BEFORE either — the LANE/SCOPE refusal, most of all. Under `set -u` an unset one does
  # not degrade the row, it KILLS the handler mid-printf and the exit attests nothing at all: the
  # instrument's own blast radius exceeding itself, in the one arm added to widen coverage
  # (memory: addon-failure-exceeds-its-blast-radius). Resolved lazily and only when missing, so the
  # hot path pays nothing and the cold path still names which repo and branch died.
  if [[ -z "${REPO_ROOT:-}" ]]; then
    REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    BRANCH="${BRANCH:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')}"
  fi
  BRANCH="${BRANCH:-?}"
  local log; log="${LAND_LOG:-$HOME/.claude/land.log}"
  mkdir -p "$(dirname "$log")" 2>/dev/null || true
  # `red` has THREE states and they must never collapse into two (memory:
  # sensor-default-off-makes-blindness-the-shipping-path — one value serving both "answered no" and
  # "could not ask" fabricated 80 of 156 findings). "" = no arm went red on this land. A named list
  # = these arms did. "unattributed" = a red WAS raised and no arm claimed it, which indicts this
  # instrument, not the tree — so a reader can subtract it instead of miscounting it as a cause.
  local red=""
  [[ "${GATE_RED:-0}" = "1" ]] && red="${GATE_RED_WHY:-unattributed}"
  # `stage` is what stops the new exit-42 row from silently moving the gate-red denominator. A
  # stale-gate re-round is an INTERNAL signal — the same land continues — so it is one land.log row
  # per ROUND, not per attempt, and a rate computed over "every ship-land row" would now be diluted
  # by however many times siblings happened to move the trunk. `land` (the default, and the value
  # every legacy row is read as) = a terminal outcome of the whole invocation. Consumers key on
  # ABSENT-or-`land`, so no reader had to change to keep its old answer (memory:
  # new-enum-member-falls-into-fail-closed-default).
  local stage="${5:-land}"
  local total_s=$(( $(date +%s) - LAND_T0 ))
  printf '{"ts":"%s","tool":"ship-land","repo":"%s","branch":"%s","sid":"%s","verify":"%s","sweep":"%s","esc_scan":"%s","exit":%s,"stage":"%s","head":"%s","base":"%s","tree":"%s","gate_scope":"%s","selected_n":%s,"smoke":"%s","smoke_n":%s,"smoke_s":%s,"net":"%s","red":"%s","total_s":%s,"gate_rounds":%s,"gate_s":%s,"gate_arms_s":%s,"gate_statics_s":%s}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${REPO_ROOT}" "${BRANCH}" "${CLAUDE_CODE_SESSION_ID:-}" \
    "$1" "$2" "$3" "$4" "$stage" \
    "${ATTEST_HEAD:-?}" "${ATTEST_BASE:-?}" "${ATTEST_TREE:-?}" "${LANE}" "${SELECTED_N:--1}" \
    "${SMOKE_STATE:-none}" "${SMOKE_N:-0}" "${SMOKE_S:-0}" "${NET_STATE:-none}" "${red}" \
    "$total_s" "${MEAS_ROUNDS:-0}" "${MEAS_GATE_S:-0}" "${MEAS_ARMS_S:-0}" "${MEAS_STATICS_S:-0}" \
    >> "$log" 2>/dev/null || true
  ATTESTED=1
  # THE CROSS-PROCESS HALF OF THE LATCH. The locked phase is a separate process behind land-lock, so
  # its ATTESTED cannot be seen by the outer that will propagate its exit code — and the outer's own
  # EXIT trap would then write a SECOND row for the same outcome. A file, because that is the only
  # channel two processes share here, and keyed on the outer's pid like the post-state handover it
  # sits beside. Absent marker ⇒ the outer attests, which is the right answer for the cases where
  # nobody could have: land-lock's own exit 75 (the lock was never acquired, so the child never ran)
  # and an untrappable SIGKILL of the child.
  if [[ "${LIFECYCLE_ROLE:-}" = "locked" && -n "${SHIP_LAND_POST_STATE:-}" ]]; then
    : > "${SHIP_LAND_POST_STATE}.attested" 2>/dev/null || true
  fi
  return 0
}

rollback_clean() {  # T-P9-7: abort any in-progress rebase so ship-land never exits on a wedged tree.
  # A no-op (harmless non-zero, suppressed) when no rebase is in progress — so it also serves as the
  # clean-tree guarantee on the retry-exhaustion path where nothing was mid-flight. Our commits and
  # the ship/backup-* ref are left intact either way; rollback undoes only a half-applied replay.
  git rebase --abort >/dev/null 2>&1 || true
}

# ---- P4: EVERY LAND TERMINATES LOUDLY, AUTHOR PRESENT OR NOT ----------------
# (land-architecture-100p-2026-08-10 §5 P4 / §2.A / §2.F.) Three defects, one lifecycle:
#
#   1. NO SIGNAL TRAP. This script installed no TERM/INT/HUP trap, so a harness process-group
#      SIGKILL — the exit-144 / #127 class — recorded NOTHING: no land.log line, no marker
#      removed, no notice. And that is the COMMON path, not the rare one: a turn cannot hold a
#      contended land (Bash-tool ceiling 600 s < episode p90 991 s), so `run_in_background` is
#      the only workable shape, and it is exactly the shape that sits behind the group kill.
#      SIGKILL itself is untrappable — nothing can fix that — but every SIGNALLED death that IS
#      trappable now attests, and the in-flight marker's pid+lstart liveness covers the residue a
#      SIGKILL leaves behind (see land_inflight_live).
#   2. NO FAILURE INBOX. A failed land's notice died with its pane: the only record was stderr in
#      a terminal whose session is gone. Now every non-zero terminal exit past the point where a
#      land actually STARTED writes a `refs/land/failed/<ts>-<sid>-<branch>` ref (durable, in the
#      repo, survives the worktree) AND files a `cc-backlog needs` row carrying the EXACT re-land
#      command — so a dead author's failed land renders at the next close of whoever reads the
#      ledger, instead of being discovered by its absence.
#   3. NO IN-FLIGHT MARKER. See hooks/lib/land-inflight.sh for the full statement; the producer
#      half is here. The refusal below is the "second concurrent fire on the same worktree" arm.
#
# The signal handler follows bin/cc-await-ping's `_sig_verdict` dialect deliberately — same shape,
# same `128 + signum` exit, same "this was TERMINATED from outside, it did not fail" wording — so
# there is ONE way this fleet attests a signalled death, not two.
LIFECYCLE_ROLE="outer"   # the locked child sets "locked": it attests, but owns no marker and files no inbox
INFLIGHT_FILE=""         # non-empty ⇒ THIS process claimed the worktree's in-flight marker

# ── LAND_MAIN_ROOT — THE DURABLE CHECKOUT, RESOLVED WHILE IT IS STILL RESOLVABLE ─────────────────
# The failure inbox runs from a TRAP, and by then this land's cwd may no longer be a git worktree at
# all: desk-land.sh hands us a THROWAWAY worktree (`$WTROOT/.desk-land-<branch>-<pid>`) and removes
# it in its own EXIT trap, so on a signalled death the two teardowns race. Measured 2026-08-18 —
# with the admin entry gone and the directory still standing, `git rev-parse --show-toplevel` fails
# and cc-backlog's project_default falls back to `basename $(pwd)`, i.e. to the SANDBOX NAME.
#
# That name carries a PID, and the backlog id is `sha256(project ⑟ title ⑟ source)`. So the row's
# identity was a function of which process happened to observe the failure: one stuck branch
# (claude/fire-20260818T080549Z-15840-1) minted FOUR blocked rows on 2026-08-18 —
# 1285df22b72e / 9776708bc201 / 2ee586a548f8 / e24b0f9933b7 — byte-identical in title, source and
# condition, differing ONLY in `project=.desk-land-…-32615 / -39245 / -42721 / -93241`.
#
# 🚨 THE STORE IS NOT BROKEN AND THE HASH MUST NOT BE WIDENED. A scratch-store probe (three `add`s,
# same title+source+condition) collapses to ONE id. The key works; the CALLER fed it a per-attempt
# input. This is the same lesson as the `--run` path a few hundred lines down — that one already
# resolves the durable checkout because a `cd` into a reaped sandbox is unrunnable — the identity
# simply never learned it. The fix is to resolve ONCE, EARLY, and hand the answer to the trap:
# a value captured while the worktree is alive cannot be un-resolved by its teardown.
#
# It is the SECOND face of e3b966424 (machine producers inflating `blocked`). That commit stopped
# `venue=cloud` misfiling and taught the recurrence brake to keep two branches apart; neither half
# can see this one, because the brake groups BY PROJECT and these rows disagree on exactly that
# field — so the fold never even considered them siblings.
LAND_MAIN_ROOT=""        # the durable main checkout — see resolve_main_root; "" until main_outer runs

# resolve_main_root <dir> → the durable main checkout backing <dir>, or <dir> when it is already one.
# A linked worktree's `--git-common-dir` IS the main checkout's `.git`, so this holds for any
# worktree, not merely the desk-land shape; SHIP_LAND_LAND_ROOT lets a caller that KNOWS the answer
# (desk-land.sh does — it created the throwaway) state it rather than have us infer it.
# Silent on failure BY DESIGN: it returns <dir> unchanged, which is exactly today's behaviour, so a
# repo layout this cannot read degrades to the old identity instead of to a wrong one.
resolve_main_root() {
  local d="${1:-}" gcd m
  [[ -n "${SHIP_LAND_LAND_ROOT:-}" && -d "${SHIP_LAND_LAND_ROOT:-}" ]] && { printf '%s' "$SHIP_LAND_LAND_ROOT"; return 0; }
  [[ -n "$d" ]] || return 0
  gcd="$(git -C "$d" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [[ -n "$gcd" ]]; then
    m="${gcd%/worktrees/*}"; m="${m%/.git}"
    [[ -n "$m" && -d "$m" ]] && { printf '%s' "$m"; return 0; }
  fi
  printf '%s' "$d"
}
# shellcheck source=/dev/null
[[ -r "${SCRIPT_DIR}/../hooks/lib/land-inflight.sh" ]] && . "${SCRIPT_DIR}/../hooks/lib/land-inflight.sh"

# P3 (963bbebe7c9a): the blob-sha-keyed statics memo. The path is an override for the same reason
# every SHIP_LAND_*_LINT above is one — so a test can substitute a NAIVE control memo and prove
# which assertion each mechanism is carrying (tests/fixtures/gate-memo-naive.sh). Default is the
# real library; an override that does not resolve degrades to the stubs below, never to a green.
MEMO_LIB="${SHIP_LAND_MEMO_LIB:-${SCRIPT_DIR}/lib/gate-memo.sh}"
# shellcheck source=/dev/null
[[ -r "$MEMO_LIB" ]] && . "$MEMO_LIB"
# DEGRADE-TO-THE-OLD-GATE STUBS. `memo_partition` decides WHICH FILES the linters are handed, so an
# absent lib would not merely disable an optimisation — the call site becomes `command not found`,
# the todo lists come back EMPTY, and the gate would skip shellcheck entirely and call it green.
# That is the exact fail direction the memo exists to forbid, so the degraded path is written out
# rather than assumed: with no lib every file is "unproven", every check runs, and the gate behaves
# exactly as it did before P3. Same reason the sourcing above is `-r`-guarded rather than required.
if ! declare -F memo_partition >/dev/null 2>&1; then
  # shellcheck disable=SC2034,SC2329  # MEMO_OK is read by the lib's consumers; these stubs are
  # invoked only on the lib-absent path, which is exactly why they cannot be proven called here.
  memo_init() { MEMO_OK=0; return 1; }
  # shellcheck disable=SC2329
  memo_file_hit() { return 1; }
  memo_file_record() { return 0; }
  memo_partition() { shift; printf '%s\n' "$@"; }
  memo_count() { :; }
  memo_summary() { return 0; }
fi

inflight_claim() {  # 0 = claimed · refuses (exit 11) when a LIVE land already owns this worktree
  local f live pid age
  # Both symbols, because the marker is only adjudicable if writer and reader share ONE lstart
  # dialect: an older deployed lib without li_lstart ⇒ no marker at all, i.e. today's behaviour,
  # rather than a marker no reader can match (see hooks/lib/land-inflight.sh § DIALECT).
  command -v land_inflight_path >/dev/null 2>&1 || return 0   # lib absent ⇒ no marker, today's behaviour
  command -v li_lstart >/dev/null 2>&1 || return 0
  f="$(land_inflight_path .)" || return 0
  if live="$(land_inflight_live . 2>/dev/null)"; then
    pid="${live%% *}"; age="$(( $(date +%s) - $(printf '%s' "$live" | cut -d' ' -f2) ))"
    echo "✗ ship-land: a land is ALREADY IN FLIGHT for this worktree (pid ${pid}, ${age}s) — refusing to fire a second one. Two lands from one worktree share a HEAD and a rebase, and the second only queues behind the first on the machine-wide mutex. Await its verdict (the ledger reports LANDING), or if that pid is wedged see: $LAND_LOCK --status" >&2
    exit 11
  fi
  # A stale marker (its writer SIGKILLed) is simply overwritten — land_inflight_live already
  # adjudicated it dead by pid+lstart, and re-adjudicating here would be a second predicate.
  {
    printf 'pid=%s\n'     "$$"
    printf 'lstart=%s\n'  "$(li_lstart "$$")"
    printf 'started=%s\n' "$(date +%s)"
    printf 'branch=%s\n'  "${BRANCH:-?}"
    printf 'head=%s\n'    "$(git rev-parse HEAD 2>/dev/null || echo '?')"
    printf 'sid=%s\n'     "${CLAUDE_CODE_SESSION_ID:-}"
  } > "$f" 2>/dev/null || return 0
  INFLIGHT_FILE="$f"
  return 0
}

# shellcheck disable=SC2329  # invoked indirectly — its callers are the two trap handlers below.
inflight_release() {  # idempotent · only ever removes a marker THIS process wrote
  [[ -n "${INFLIGHT_FILE:-}" ]] || return 0
  rm -f "$INFLIGHT_FILE" 2>/dev/null || true
  INFLIGHT_FILE=""
  return 0
}

# THE FAILURE INBOX. Two stores, because they answer different questions and fail independently:
# the ref is durable repo state (it survives the pane, the worktree and the machine, and it pins
# the exact head that failed to land, so the work is recoverable by anyone); the backlog row is
# what makes it RENDER — an operator-owned step in the store `operator-readout.sh` already reads,
# so it appears at the next close of whoever reads the ledger (memory:
# conclusion-must-reach-the-enforcing-store — a ref nothing reads is inert).
# shellcheck disable=SC2329  # invoked indirectly — its callers are the two trap handlers below.
land_failure_inbox() {  # $1=exit code $2=cause word
  local rc="$1" cause="$2" head name ref cmd bl id oracle fout frc land_root land_proj _lgcd _lmain
  # ONLY past the in-flight claim, i.e. only once a land actually STARTED. Preflight refusals
  # (dirty tree, shared checkout, a second concurrent fire) are the author's own immediate,
  # visible feedback and filing them would drown the inbox in noise the author already read.
  [[ -n "${INFLIGHT_FILE:-}" ]] || return 0
  head="$(git rev-parse HEAD 2>/dev/null || true)"
  if [[ -n "$head" ]]; then
    name="$(printf '%s-%s-%s' "$(date -u +%Y%m%dT%H%M%SZ)" "${CLAUDE_CODE_SESSION_ID:-nosid}" "${BRANCH:-nobranch}" \
            | tr -c 'A-Za-z0-9._-' '-')"
    ref="refs/land/failed/${name}"
    git update-ref "$ref" "$head" 2>/dev/null || true
  fi
  # THE RE-LAND COMMAND MUST OUTLIVE THE ATTEMPT THAT FILED IT. $REPO_ROOT is frequently the
  # per-attempt sandbox (`/private/tmp/.desk-land-<branch>-<pid>`), which is reaped — so a row whose
  # `--run` cd's there is unrunnable by the time anyone reads it, and now that the recurrence brake
  # folds these rows (below) the FIRST attempt's path would be cemented for every later one.
  # Resolve the durable main checkout the same way handoff-fire's recycle fallback does.
  # LAND_MAIN_ROOT was resolved in main_outer, while the worktree was still a worktree. Prefer it;
  # the inline resolution below stays as the fallback for the paths that never reached main_outer.
  land_root="${LAND_MAIN_ROOT:-$REPO_ROOT}"
  case "$land_root" in
    /tmp/*|/private/tmp/*|/var/folders/*)
      _lgcd="$(git -C "$land_root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
      if [[ -n "$_lgcd" ]]; then
        _lmain="${_lgcd%/worktrees/*}"; _lmain="${_lmain%/.git}"
        [[ -d "$_lmain" ]] && land_root="$_lmain"
      fi ;;
  esac
  # 🚨 THE RETRY RUNS TRUNK'S PIPELINE AGAINST THE BRANCH — NEVER THE BRANCH'S OWN COPY OF IT
  # (2026-08-16, BACKLOG_DRAIN_24_7 §4 C1). This line used to end `bash scripts/ship-land.sh`: a
  # RELATIVE path, resolved inside the branch that had just been checked out. So retrying a stuck
  # branch executed THAT BRANCH'S ship-land.sh, and every brake landed on trunk since the branch was
  # cut was structurally unreachable from the one code path that most needs them — the retry of an
  # OLD branch is by definition the case where the branch's pipeline is most out of date. Both of
  # this generator's own brakes were in that blind spot: aa1886a5e's one-row-per-stuck-branch title
  # fold and 40613b786's rc-5 content-already-on-trunk screen, i.e. the two fixes that exist to stop
  # this very function minting duplicates. Measured leak: row accec6d1f40c (2026-08-16T08:26Z)
  # postdates aa1886a5e by fifteen minutes and still carries the pre-fold title format.
  #
  # THE MECHANISM IS A SEPARATION THIS FILE ALREADY RELIES ON, not a new one. SCRIPT_DIR is resolved
  # from $SELF (see _resolve_self above) and supplies the PIPELINE — land-lock, land-verify,
  # gate-select, gate-policy, gate-memo, postland-verify; REPO_ROOT and BRANCH come from the CWD and
  # supply the TREE BEING LANDED. The lint paths a few hundred lines down are deliberately resolved
  # repo-root-relative rather than from SCRIPT_DIR for exactly this reason ("the tree being landed
  # must be gated by its own"). So running trunk's ship-land.sh from inside the branch checkout is
  # not a trick — it is the split this script is already built around, finally used on the retry.
  #
  # WHY A THROWAWAY WORKTREE AND NOT THE TWO OBVIOUS ALTERNATIVES, both of which were tried:
  #   · `git show origin/main:scripts/ship-land.sh > /tmp/x && bash /tmp/x` — SCRIPT_DIR becomes
  #     /tmp and EVERY sibling above resolves to nothing. gate-select absent is not an error, it is
  #     the documented fail-closed FULL-corpus branch, i.e. the 2026-07-26 gate-runaway amplifier.
  #   · `git checkout origin/main -- scripts/` into the branch tree — that dirties the working tree,
  #     and a dirty tree is a ship-land PREFLIGHT REFUSAL. The retry would never start.
  # A detached worktree at origin/main is the only variant where trunk's bytes AND all their siblings
  # resolve while the branch checkout stays clean. It is removed unconditionally afterwards: the
  # branch this exists for is precisely the one retried dozens of times, and a retry that accumulates
  # a worktree per attempt would be a second minter wearing a fix's clothes.
  #
  # The teardown is guarded on $_tw being set rather than sharing the `&&` chain, because a `;`
  # teardown still runs when its setup failed (memory: destructive-cleanup-runs-after-its-setup-
  # failed) — here that would hand `git worktree remove --force` an empty path. The static half is
  # SINGLE-quoted so `$_tw`/`$_rc` survive to run time; only land_root and BRANCH interpolate now.
  # shellcheck disable=SC2016  # the single quotes are the POINT — $_tw/$_rc must survive unexpanded
  # into the stored command and be evaluated by the shell that RUNS it, not by this one. Expanding
  # them here would bake this trap handler's own (empty) values into an operator's re-land step.
  cmd="cd ${land_root} && git checkout ${BRANCH} && "'_tw="$(mktemp -d)/trunk" && git fetch origin --quiet && git worktree add --detach "$_tw" origin/main >/dev/null && bash "$_tw/scripts/ship-land.sh"; _rc=$?; [ -n "${_tw:-}" ] && git worktree remove --force "$_tw" >/dev/null 2>&1; exit $_rc'
  # A FIXTURE pipeline must never file into the operator's live ledger — tests/ship-land.bats
  # drives ~50 of them, several deliberately non-zero. Same discipline as gate_home_setup's
  # bats detection, and `on` forces it so the suite can prove the real thing against its own
  # CC_BACKLOG_FILE. The REF half is repo-local (a fixture repo is a tmpdir), so it always runs
  # and is always assertable without a force.
  if [[ -n "${BATS_TEST_TMPDIR:-}${BATS_SUITE_TMPDIR:-}" && "${SHIP_LAND_FAILURE_INBOX:-auto}" != "on" ]]; then
    return 0
  fi
  [[ "${SHIP_LAND_FAILURE_INBOX:-auto}" = "off" ]] && return 0
  bl="${CC_BACKLOG_BIN:-$HOME/.claude/bin/cc-backlog}"
  [[ -x "$bl" ]] || return 0
  # The id is CAPTURED now (it used to go to /dev/null) because the row needs a falsifier, and
  # `falsify` is the only door to one: `needs --falsifier` reaches cmd_add, which returns early on a
  # known id, so it is a silent no-op on any row the recurrence brake folds onto.
  # 🚨 THE TITLE IS THE IDENTITY, SO IT MUST HOLD ONLY WHAT IS STABLE ACROSS ATTEMPTS (2026-08-16).
  # This title used to embed three per-attempt facts — the sandbox path `(${REPO_ROOT})`, the exit
  # `${rc} (${cause})`, and the pinned `${ref}` — and cc-backlog's recurrence brake keys on the
  # title ("same prose, same subject modulo digits"). Digits normalise; a different PID-suffixed
  # /private/tmp path does not, and neither does `143 (SIGTERM)` vs `6 (exit)`. So every retry
  # minted a SIBLING instead of folding, and one stuck branch became a population:
  # `claude/fire-20260812T172113Z-3600-1` had **41 rows** in the live store on 2026-08-16, 9 of
  # them filed that day, all naming the identical operator step. That is not inflow — it is one
  # failure re-counted 41 times, and it is a large share of a blocked pile nothing drains.
  #
  # The branch IS the identity: one stuck branch is one job to do, however many times the retry
  # loop notices. The volatile diagnostics move to the `--run` command, which cc-do renders
  # verbatim, so nothing an operator needs to act is lost — only the false distinctness is.
  #
  # 🚨 AND THE PROJECT IS HALF THAT IDENTITY, WHICH IS WHY IT IS PASSED EXPLICITLY (2026-08-18).
  # The id is `sha256(project ⑟ title ⑟ source)`, and this call used to send no --project at all —
  # so cc-backlog derived one from ITS OWN CWD, which on the desk-land path is the per-attempt
  # throwaway worktree. Stabilising the TITLE (above) therefore fixed only one of the two hashed
  # fields: every retry still minted a sibling, now differing in a field the title fold cannot even
  # see, because the recurrence brake GROUPS BY PROJECT. Four rows for one branch, measured.
  #
  # land_root is the durable checkout resolved in main_outer, so this label is the same string on
  # every attempt however many sandboxes observe the failure. A leading dot can only be a sandbox
  # (`.desk-land-…`) and never a project, so it is refused rather than filed — falling through to
  # the old cwd-derived default, which is exactly today's behaviour and not a worse one. The label
  # is checked against scripts/dispatch-projects.conf at the chokepoint (WARN, never refuse), so a
  # repo with no conf row still files; see EXPLICIT --project VALIDATION in cc-backlog.
  land_proj="$(basename "$land_root" 2>/dev/null || true)"
  local -a nargs
  # The title stays ALONE on its own line: tests/ship-land.bats reads this call site structurally
  # (it cannot call a trap handler without a full failing land) and asserts the emitted title's
  # SHAPE — no sandbox path, no exit code, the branch present.
  nargs=(needs
    "re-land ${BRANCH}: ship-land could not complete and its author's pane may be gone"
    --run "$cmd   # last attempt: rc=${rc} (${cause}), head pinned at ${ref:-<unrecorded>}"
    --session "${CLAUDE_CODE_SESSION_ID:-}")
  case "$land_proj" in
    ""|.*) : ;;                                  # unresolvable, or a sandbox — do not file a lie
    *) nargs=("${nargs[@]}" --project "$land_proj") ;;
  esac
  id="$("$bl" "${nargs[@]}" 2>/dev/null || true)"
  # THE FALSIFIER — the half that was missing, and the reason this population rotted. A row filed
  # here measures ONE thing: that ship-land exited non-zero. It never re-asks, so it is a PREDICTION
  # about content, and the prediction is usually wrong within a day: censused 2026-08-12, 24 of the
  # 25 `re-land …` rows of the master-stranded-work effort were false — the work had landed under a
  # different sha — and actioning four of them would have REVERTED trunk.
  #
  # land-content-verify.sh exits 0 exactly when the pinned ref's content is on trunk, which is the
  # RETRACTING direction, so `falsify` screens it before storing: at filing time the content is
  # genuinely not on trunk (exit 1) and it stores; a probe that already exits 0 is REFUSED (rc 5),
  # which is the store telling us this row should never have been filed.
  #
  # 🚨 BOTH OUTCOMES ARE CORRECT; SWALLOWING THEM WAS NOT — and that is what this block used to do
  # (`>/dev/null 2>&1 || true`, output AND rc discarded). A refusal leaves the row filed with NO
  # probe, and a probe-less row is in NEITHER of the retractor's buckets: it cannot self-retract
  # and nothing reports it, so it is permanently live. MEASURED 2026-08-13 on a live instance — row
  # cdeb77e34952, `re-land claude/fire-20260812T172113Z-3600-1`, ship-land exited 143/SIGTERM —
  # filed with falsifier=NONE (item b15a2984d134). What is still true is the exit-code discipline:
  # this runs from a trap handler, so every branch below returns 0 and a land must never fail
  # because a backlog row could not be annotated. Reading an rc is not touching one.
  #
  # No ref ⇒ no probe: a falsifier over `<unrecorded>` could only ever answer "cannot tell", and a
  # probe that cannot answer is worse than none (memory: sensor-default-off-makes-blindness-the-
  # shipping-path). Same for a checkout that predates the oracle.
  oracle="${REPO_ROOT}/scripts/land-content-verify.sh"
  if [[ -n "$id" && -n "$ref" && -x "$oracle" ]]; then
    fout="$("$bl" falsify "$id" --probe "bash ${oracle} ${ref}" 2>&1)"; frc=$?
    if [[ "$frc" -eq 5 ]]; then
      # rc 5 ⇒ the probe exits 0 RIGHT NOW ⇒ the oracle says this ref's content is ALREADY on
      # trunk: the land died AFTER its content landed, and there is nothing to re-land. So this is
      # the generator's missing precondition — CONTAINMENT TESTED BEFORE THE ROW PERSISTS — paid
      # for with the one oracle run `falsify` already makes, rather than a second pre-check ahead
      # of the filing (this handler may be running under a signal; it must not double a fetch).
      # Closing is cc-backlog's own prescription for this refusal: "the item is genuinely already
      # finished. Then CLOSE it, do not probe it."
      # `done` is QUOTED because it is a shell keyword: bare, shellcheck reads it as an unterminated
      # loop body (SC1010) and the gate's own lint goes red on this file.
      "$bl" "done" "$id" --evidence \
        "auto-retracted at filing: ${oracle##*/} reports ${ref}'s content already on trunk, so this land died after its content landed and there is nothing to re-land (cc-backlog falsify REFUSED the probe, rc 5)" \
        >/dev/null 2>&1 || true
      printf '· ship-land: re-land row %s CLOSED at filing — %s is already on trunk\n' "$id" "$ref" >&2
    elif [[ "$frc" -ne 0 ]]; then
      # Every other non-zero has no remedy from here, but it leaves the same probe-less row — so
      # saying so IS the fix. An unreported one is indistinguishable from a healthy filing.
      printf '⚠ ship-land: re-land row %s was filed WITHOUT a falsifier (cc-backlog falsify rc=%s) — it cannot self-retract, so retract it by hand once %s is on trunk.\n  %s\n' \
        "$id" "$frc" "$ref" "${fout:-<no output>}" >&2
    fi
  fi
  return 0
}

# shellcheck disable=SC2329  # invoked indirectly — the three `trap` lines at dispatch are its only callers.
_land_sig_verdict() {  # <signame> <signum>
  trap - TERM HUP INT EXIT
  local rc=$(( 128 + $2 ))
  gate_home_teardown
  rollback_clean
  # THE ATTESTATION IS THE WHOLE POINT: without it a killed land is indistinguishable from a land
  # that never ran, and 100% of the exit-144 population read as absence rather than death.
  attest_land "killed" "n/a" "n/a" "$rc"
  if [[ "$LIFECYCLE_ROLE" = "outer" ]]; then
    land_failure_inbox "$rc" "SIG$1"
    inflight_release
  fi
  # ── NAME WHAT WE CAN SEE OF THE SENDER (2026-08-17). This line asserted "TERMINATED from outside"
  # for every TERM — a claim about an ACTOR the handler never looked for, and wrong often enough to
  # matter: a caller's own `timeout`/`gtimeout` wrapper produces exactly this signal, and 2 of the
  # 11 residual kills in the 2026-08-17 census were the investigator's own bound while the banner
  # blamed a peer. A verdict that cannot separate "a peer killed us" from "our own bound fired"
  # sends every reader to the wrong fix (memory: timeout-rc-collides-with-the-childs-own-rc — 124
  # has two authors, and so does 143).
  #
  # Three facts, read AT SIGNAL TIME because none of them survives the exit: our ELAPSED (a bound
  # fires at a round number, a peer does not), whether we are ORPHANED (ppid 1 is the shape every
  # cc-reaper orphan class selects on), and whether a `timeout` sits in our OWN ancestry (if it
  # does, the likeliest sender is ours). Best-effort throughout — this runs from a signal handler
  # and must never fail the exit it is annotating (memory: addon-failure-exceeds-its-blast-radius).
  local _sv_el _sv_pp _sv_anc="" _sv_p _sv_n=0 _sv_src="sender UNKNOWN"
  _sv_el=$(( $(date +%s) - ${LAND_T0:-$(date +%s)} ))
  _sv_pp="$(ps -o ppid= -p $$ 2>/dev/null | tr -d ' ')"; [ -n "$_sv_pp" ] || _sv_pp="?"
  _sv_p="$_sv_pp"
  while [ -n "$_sv_p" ] && [ "$_sv_p" -gt 1 ] 2>/dev/null && [ "$_sv_n" -lt 12 ]; do
    _sv_anc="$_sv_anc $(ps -o ucomm= -p "$_sv_p" 2>/dev/null | tr -d ' ')"
    _sv_p="$(ps -o ppid= -p "$_sv_p" 2>/dev/null | tr -d ' ')"; _sv_n=$(( _sv_n + 1 ))
  done
  case "$_sv_anc" in *timeout*) _sv_src="a TIMEOUT is in our OWN ancestry — the likeliest sender is our own bound, not a peer" ;; esac
  [ "$_sv_pp" = "1" ] && _sv_src="we are ORPHANED (ppid 1) — the shape every cc-reaper orphan class selects on"
  echo "✗ ship-land: verdict=killed signal=SIG$1 role=${LIFECYCLE_ROLE} branch=${BRANCH:-?} elapsed=${_sv_el}s ppid=${_sv_pp} ancestry=[${_sv_anc# }] — ${_sv_src}. This land did not fail a gate and nothing was proven about the tree; the work is still on ${BRANCH:-the branch}." >&2
  exit "$rc"
}

# shellcheck disable=SC2329  # invoked indirectly via `trap _land_exit_trap EXIT` at dispatch.
_land_exit_trap() {
  local rc=$?
  trap - EXIT
  # COMPOSED, not competing: gate_home_setup used to install its own EXIT trap and its header said
  # any second one "must compose with this". This IS that composition — one EXIT handler, teardown
  # first (it is idempotent and refuses to remove anything it did not create), lifecycle second.
  gate_home_teardown
  # ---- P0: ATTEST EVERY TERMINAL EXIT ----------------------------------------
  # (§2.B: "exits 2/4/7/42 and the in-lock fallback's exit-6 write no attestation row".) Measured on
  # the live store the day this landed: 14 days of ship-land rows carry ONLY exits 0, 3, 6 and 143 —
  # five ways for a land to die left the ledger reading as though the land had never been attempted,
  # which is the same blindness P4 removed for signalled deaths.
  #
  # HERE, not at the exit sites, and for the same reason P4 put the signal verdict in a trap: there
  # are fourteen `exit` statements across two roles, the set grows, and a rule enforced at each site
  # is a rule the next author does not know about. The trap is the one place every terminal exit
  # passes through. It is deliberately NARROW — non-zero only. A zero exit either already attested
  # (the landed path) or is a "nothing to land" / `--dry-run` no-op, and minting a success row for
  # those would inflate the very denominator this work exists to make readable.
  #
  # FAILS NO WIDER THAN ITSELF (memory: addon-failure-exceeds-its-blast-radius): attest_land's write
  # is `|| true`, the latch is a variable, and this arm cannot change `rc` — an instrument that
  # could fail a land would be worse than the blindness it replaces.
  # ONE EXCEPTION, and it is the exit that is not an outcome: 42 is the locked child's INTERNAL
  # stale-gate signal to the outer loop, which owns that row and writes it as stage:"round" with the
  # mutex already released. Left to this trap the child would write a stage:"land" row for a land
  # that is still running — a phantom terminal outcome, and one that would land in every rate's
  # denominator. Only the locked role is exempted, because 42 never escapes ship-land: if it ever
  # reached the outer as a terminal code, that WOULD be an outcome and should attest as one.
  if [[ "$rc" -ne 0 && "${ATTESTED:-0}" != "1" ]] \
     && ! { [[ "$rc" -eq 42 && "$LIFECYCLE_ROLE" = "locked" ]]; }; then
    attest_land "n/a" "n/a" "n/a" "$rc"
  fi
  if [[ "$LIFECYCLE_ROLE" = "outer" ]]; then
    [[ "$rc" -ne 0 ]] && land_failure_inbox "$rc" "exit"
    inflight_release
  fi
  exit "$rc"
}

# ---- EMPTYING THE MUTEX: the locked child → outer-process handover ----------
# 2026-08-10 (land-architecture-100p §2.A / §5 P1). stranded-sweep (measured 59-62s, O(497 refs)
# and growing with every branch anyone ever creates) and ship-backup-reap used to run INSIDE the
# land-lock. They were ~90% of an 87s median hold, for work the lock does not protect — the thing
# the lock actually exists for, land-verify, is 0.485s. Every other lander on the box queued behind
# a sweep that had nothing to do with the race window, and the cost grew monotonically with the
# ref count, so the mutex got worse every week on its own.
#
# BOTH MOVE OUT, and the move is sound because NEITHER reads live trunk state that the lock could
# stabilise. This is the whole correctness argument, so it is stated per tool rather than asserted:
#   · ship-backup-reap's predicate is (backup-ref, LANDED_HEAD) and NOTHING else. Its own header
#     is explicit that it must never re-read origin/<trunk> — against a drifted trunk the same
#     predicate misclassifies 437 of 739 refs — so it was already written to be independent of when
#     it runs relative to a sibling's land. Releasing the lock first cannot change one bit of it.
#   · stranded-sweep is REVIEW-only advisory (exit 1 is a prompt, not a verdict) and re-fetches the
#     trunk itself. A sibling advancing the trunk after our release can only ADD content to it, and
#     the sweep flags a commit only when ALL its paths are ABSENT from the trunk — so a later read
#     is monotone in the SAFE direction: it can flag fewer commits, never more, and never ours.
# What it cannot do is drop the attestation: `sweep=` still populates, because the outer process
# performs the attest after the sweep, exactly as the locked child used to.
#
# The child hands over the facts the outer cannot recompute. Most it could (HEAD is shared — same
# worktree), but the FALLBACK lane's gate facts are the child's alone: there the gate ran in the
# child, so LANE/SELECTED_N/SMOKE_*/NET_STATE exist only there, and an outer that re-derived them
# from its own unset globals would attest a smoke nobody ran. One file, whitelisted keys, removed
# on read.
post_state_path() {  # $1=key — inside the git dir: never the worktree, never tracked, never /tmp
  local gc; gc="$(git rev-parse --git-common-dir 2>/dev/null || echo .git)"
  case "$gc" in /*) ;; *) gc="$(cd "$gc" 2>/dev/null && pwd || echo "$gc")" ;; esac
  printf '%s/ship-land-post-%s' "$gc" "$1"
}

meas_export() {  # P0: carry the measurement across the locked re-exec, like the SMOKE_* handover
  # T0 is the load-bearing one: without it the child's `total_s` would restart at its own first
  # line and report the LOCKED phase's duration under a field named end-to-end — a number that is
  # not wrong so much as answering a different question, which is the failure mode this whole item
  # exists to remove.
  export SHIP_LAND_T0="$LAND_T0" \
         SHIP_LAND_MEAS_ROUNDS="$MEAS_ROUNDS" SHIP_LAND_MEAS_GATE_S="$MEAS_GATE_S" \
         SHIP_LAND_MEAS_ARMS_S="$MEAS_ARMS_S" SHIP_LAND_MEAS_STATICS_S="$MEAS_STATICS_S"
}

child_attested_absorb() {  # the cross-process half of the attest latch — see attest_land
  # The child writes this marker whenever IT attested, so the outer's EXIT trap does not write a
  # second row for one outcome. Absence is meaningful and is the safe direction: land-lock's own
  # exit 75 (never acquired ⇒ the child never ran) and an untrappable SIGKILL of the child both
  # leave no marker, and both are outcomes that would otherwise attest NOTHING at all.
  [[ -n "${SHIP_LAND_POST_STATE:-}" ]] || return 0
  if [[ -f "${SHIP_LAND_POST_STATE}.attested" ]]; then
    rm -f "${SHIP_LAND_POST_STATE}.attested" 2>/dev/null || true
    ATTESTED=1
  fi
  return 0
}

post_state_write() {  # $1=landed_head — the locked child's entire handover
  local f="${SHIP_LAND_POST_STATE:-}"
  [[ -n "$f" ]] || return 0
  {
    printf 'LANDED_HEAD=%s\n'  "$1"
    printf 'ATTEST_HEAD=%s\n'  "${ATTEST_HEAD:-?}"
    printf 'ATTEST_BASE=%s\n'  "${ATTEST_BASE:-?}"
    printf 'ATTEST_TREE=%s\n'  "${ATTEST_TREE:-?}"
    printf 'LANE=%s\n'         "${LANE}"
    printf 'SELECTED_N=%s\n'   "${SELECTED_N:--1}"
    printf 'SMOKE_STATE=%s\n'  "${SMOKE_STATE:-none}"
    printf 'SMOKE_N=%s\n'      "${SMOKE_N:-0}"
    printf 'SMOKE_S=%s\n'      "${SMOKE_S:-0}"
    printf 'NET_STATE=%s\n'    "${NET_STATE:-none}"
    printf 'GATE_RED=%s\n'     "${GATE_RED:-0}"
    printf 'GATE_RED_WHY=%s\n' "${GATE_RED_WHY:-}"
    # P0: the fallback lane gates INSIDE the child, so these are the child's alone — the same
    # reason SMOKE_* is here. An outer that re-derived them from its own globals would attest a
    # gate_rounds one short and a gate_s that excludes the only round that ran.
    printf 'MEAS_ROUNDS=%s\n'     "${MEAS_ROUNDS:-0}"
    printf 'MEAS_GATE_S=%s\n'     "${MEAS_GATE_S:-0}"
    printf 'MEAS_ARMS_S=%s\n'     "${MEAS_ARMS_S:-0}"
    printf 'MEAS_STATICS_S=%s\n'  "${MEAS_STATICS_S:-0}"
  } > "$f" 2>/dev/null || true
}

post_state_read() {  # $1=file — one explicit arm per key: no `eval`, so a corrupted or hand-edited
                     # handover can only be IGNORED, never executed.
  local line k v
  while IFS= read -r line; do
    k="${line%%=*}"; v="${line#*=}"
    case "$k" in
      LANDED_HEAD)  LANDED_HEAD="$v"  ;;
      ATTEST_HEAD)  ATTEST_HEAD="$v"  ;;
      ATTEST_BASE)  ATTEST_BASE="$v"  ;;
      ATTEST_TREE)  ATTEST_TREE="$v"  ;;
      LANE)         LANE="$v"         ;;
      SELECTED_N)   SELECTED_N="$v"   ;;
      SMOKE_STATE)  SMOKE_STATE="$v"  ;;
      SMOKE_N)      SMOKE_N="$v"      ;;
      SMOKE_S)      SMOKE_S="$v"      ;;
      NET_STATE)    NET_STATE="$v"    ;;
      GATE_RED)     GATE_RED="$v"     ;;
      GATE_RED_WHY) GATE_RED_WHY="$v" ;;
      MEAS_ROUNDS)     MEAS_ROUNDS="$v"     ;;
      MEAS_GATE_S)     MEAS_GATE_S="$v"     ;;
      MEAS_ARMS_S)     MEAS_ARMS_S="$v"     ;;
      MEAS_STATICS_S)  MEAS_STATICS_S="$v"  ;;
    esac
  done < "$1"
}

post_release_finish() {  # $1=trunk — runs in the OUTER process, the land-lock ALREADY RELEASED.
  # No-op unless the locked child left a handover, i.e. unless a real land happened. The child's
  # other exit-0 paths (nothing-to-land, --dry-run, a drop that self-healed because a sibling
  # landed our content) attest for themselves and write no handover, and must not be re-attested.
  local f="${SHIP_LAND_POST_STATE:-}"
  [[ -n "$f" && -s "$f" ]] || return 0
  post_state_read "$f"
  rm -f "$f" 2>/dev/null || true
  local TRUNK="$1"

  # --- discharge the rollback ref (STRANDED_EXPOSURE_2026-07-26 §8.2) ---
  # THE ONLY PLACE THIS REF MAY BE DELETED, and it is reachable only past the locked child's
  # content-verify — i.e. only once land-verify has proven this head's content is on the trunk.
  # That is exactly the ref's release condition: it exists to roll back a land that went wrong, and
  # this land did not. Left undeleted (the behaviour until 2026-07-26) every SUCCESSFUL land
  # permanently added a branch pinning the PRE-rebase commits, whose patch-ids no dedupe can
  # collapse onto their landed twins — so the "stranded" exposure metric grew monotonically with
  # landing volume, 70 of 81 orphan-carrying branches being these refs. The reaper re-proves the
  # ref's OWN content against $LANDED_HEAD before deleting (never against origin/$TRUNK, which a
  # sibling can advance under us), and KEEPS it on any doubt.
  # Ordered before the sweep purely as hygiene — the sweep walks every ref in refs/heads, so a ref
  # whose purpose is already discharged should not be in that walk. It is NOT a correctness fix for
  # the sweep: stranded-sweep only reports a commit whose paths are ALL absent from the trunk, so it
  # would not have flagged a ref we just landed.
  # `|| true` is load-bearing: a land that has already content-verified must never be turned red by
  # its own cleanup. Kill switch: SHIP_BACKUP_REAP=off.
  if [[ -n "${SHIP_LAND_BACKUP_REF:-}" && -x "$BACKUP_REAP" ]]; then
    "$BACKUP_REAP" reap "$SHIP_LAND_BACKUP_REF" "$LANDED_HEAD" || true
  fi

  # --- stranded-sweep: ATTRIBUTED, so the verdict is about US (backlog 175bce12e0e1) --------------
  # This call site was the last un-damped leg. The sweep's callee-side fixes landed 2026-08-12
  # (634ecdccbc55, fd517a5863cc) — the verdict is now a bounded count and `--mine` finally
  # ATTRIBUTES, keyed on anchors that exist (`refs/land/failed/*-<sid>-*`, plus a land.log row's
  # `head` for that sid) rather than the `Session-Id:` trailer nothing ever wrote. But the caller
  # was deliberately left alone while a sibling owned the file, so ship-land kept invoking default
  # mode and `sweep=review` kept reading ~955 of 989 lands. An alarm that fires 97% of the time
  # carries essentially no bits, and what it printed was a per-commit wall of PEER WIP the very
  # next line told the reader never to cherry-pick.
  #
  # 🚨 WHY `--mine` IS PASSED CONDITIONALLY, and why that is the load-bearing half. Before the
  # ownership fix, `--mine` could only ever match 0 commits, so making this change any earlier
  # would have swapped an always-alarm for a NEVER-alarm — the strictly worse failure, because it
  # says nothing and says it silently (memory: alarm-polarity-and-attention-budget — count
  # NOT-success). The same trap survives in one place: an EMPTY sid. `refs/land/failed/` names are
  # built with `${CLAUDE_CODE_SESSION_ID:-nosid}` (see the ref writer above), so a sid-less land
  # anchors under the literal `nosid` — and passing that as an identity would attribute EVERY
  # sid-less session's drops to this one. The callee also treats an empty `--mine` as default mode,
  # but relying on that would put this polarity guarantee in the wrong file: a later callee change
  # could flip it with nothing here to notice. So the argv is built explicitly, and no sid means no
  # `--mine` — degrade to the bounded default count, never to a confident silence.
  local sweep_out sweep_rc sweep_field
  local -a sweep_args=()
  local sweep_sid="${CLAUDE_CODE_SESSION_ID:-}"
  [[ -n "$sweep_sid" ]] && sweep_args+=(--mine "$sweep_sid")
  sweep_out="$("$STRANDED_SWEEP" "${sweep_args[@]+"${sweep_args[@]}"}" "$TRUNK" 2>&1)"; sweep_rc=$?
  if [[ "$sweep_rc" -eq 0 ]]; then
    sweep_field="clean"
    echo "✓ ship-land: stranded-sweep clean."
  else
    # `review` is kept verbatim as the attestation value: it is asserted by tests/land-gate-cas.bats
    # and read by land.log consumers, and renaming it would red an existing suite to say nothing new.
    # What changes is the PROSE, which under `--mine` is now about the lander instead of the fleet.
    sweep_field="review"
    if [[ ${#sweep_args[@]} -gt 0 ]]; then
      echo "⚠ ship-land: stranded-sweep flags YOUR OWN session's dropped commit(s) — this is attributed to session $sweep_sid, not peer WIP. Recover them via the recipes below:" >&2
    else
      echo "⚠ ship-land: stranded-sweep flags commit(s) for REVIEW — no session id, so this is the UNATTRIBUTED count over every local branch; peer WIP is expected on a multi-session box; recover ONLY your own dropped work, NEVER cherry-pick peer WIP onto $TRUNK:" >&2
    fi
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
  return 0
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
# GATE_PRECHECK is the SECOND reason run_gate may skip the bats phase, and it is deliberately a
# SEPARATE flag from IN_LAND_LOCK rather than a reuse of it. Reusing IN_LAND_LOCK would have been
# one character cheaper and would have made a precheck claim, in every message it prints and every
# branch it takes, that it holds the machine-wide land-lock — which is false, and it is exactly
# the kind of overloaded token that turns a later reader's correct inference into a wrong one.
# The two are read TOGETHER at the one place a suite can start; neither is a superset of the other.
GATE_PRECHECK="${GATE_PRECHECK:-0}"
# ---- THE CEILING IS DERIVED FROM THE BOX, NOT A CONSTANT (2026-08-08) --------------------------
# WHAT WAS WRONG: the default was the literal `8`, and on this 10-core box that is 0.8/core — a
# ceiling the machine is essentially never under. Measured consequence in ~/.claude/land.log:
# of 405 lands that reached this predicate, 352 SHED (87%); only 26 green + 16 red + 11 partial
# ever earned a behavioral verdict. So "landed green" meant "statically green only" for ~7 lands
# in 8, silently. Live instance: d6b417e9 changed bin/cc-wave-plan and left tests/cc-wave-plan.bats
# asserting the INVERSE contract; that suite is direct-selected via BOTH the literal: and naming:
# edges (un-exonerable), yet the next land recorded smoke:"skipped" and the suite stayed RED on
# trunk for a day (fixed by hand, 4926f76a).
#
# WHY 8 WAS EVER THERE — and why it stopped being the right number. It arrived in dda9e189 as
# `gate_admit`, a bounded WAIT in front of the v1 gate's FULL 126-suite corpus (20-53 min). v2
# (492c5106) deleted both the corpus and the wait and put a ≤120s, one-process-at-a-time, nice'd
# smoke behind the same predicate — but carried the NUMBER across untouched. The ceiling now
# guards something ~2 orders of magnitude cheaper than the thing it was sized for. Classic
# premise-rot: the threshold outlived the cost it was chosen against.
#
# WHY PER-CORE, AND WHY 8 OF THEM. This repo's own MACHINE_CAPACITY_V2 §8.5.7 measured THIS box
# SURVIVING 29.15-59.80 (2.92-5.98/core) across 13 samples at a CONSTANT 31-32 sessions — i.e.
# that band is ordinary heavy operation here, not distress. The same section established that
# loadavg is the wrong instrument for this decision at all: it swung 2.05x in 100 s at constant
# workload, the whole session fleet is only ~18% of process CPU, and a single iTerm2 process
# out-consumes it — so the signal is neither ATTRIBUTABLE to the gate nor SHEDDABLE by skipping
# its smoke. 8/core = 80 here, above every reading ever recorded on this box (max 62). At the
# measured band this is therefore EFFECTIVELY LOAD-INSENSITIVE by design; what survives is a
# runaway CIRCUIT-BREAKER, not a capacity model — say so rather than implying a calibration this
# number does not have (memory: threshold-must-separate-fatal-from-survived — the fatal 2.53/core
# sits BELOW the survived band, so no per-core value separates the two, and none is claimed to).
#
# THE ASYMMETRY THAT PICKS THE DIRECTION: a false RUN costs ≤120 s of one nice'd bats process on a
# box that lives at 6/core. A false SHED costs a behaviorally ungated land whose only net trails
# trunk by ~111 commits / ~20 h (measured 2026-08-08) — which is exactly the "red on trunk for a
# full day" above. When one error is bounded-and-trivial and the other is the defect being fixed,
# the ceiling belongs high.
#
# NOT the background QoS band, which was the other obvious remedy: postland keeps `background` for
# hours of bats because there wall time is deploy latency, but PRI 4 taxes the same work 4-84x
# (memory: bound-must-fit-the-band-not-the-bench), so a ≤120s budget there becomes a PERMANENT
# non-verdict — smoke:"partial" every time. That trades a loud skip for a quiet one and gates
# nothing. The smoke stays in its own band and simply runs.
#
# BACKWARD COMPATIBLE BY CONSTRUCTION: an EXPLICIT CC_GATE_MAX_LOAD is still an ABSOLUTE ceiling,
# so every existing caller keeps its exact meaning (0|off kill switch, the fixture probes, and
# tests/ship-land.bats' 0.0001/100000/31 all set it explicitly). Only the UNSET default changed.
load_above_ceiling() {  # 0 = at/above the ceiling (SHED) · 1 = below it, sensor broken, or off
  local max load ncpu percore
  # sysctl is /usr/sbin/sysctl, and /usr/sbin is absent from the PATH a LaunchAgent exports for its
  # children — so a BARE name reads the load fine from the operator's shell and does not exist for
  # any unattended caller, routing straight into the fail-OPEN arm below. The shed then never fired
  # and the gate ran its smoke on exactly the loaded box it had been told to shed from. A fail-open
  # sensor that is blind ONLY off-session is the worst available polarity: green where a human tests
  # it, dead where it runs. Measured at trunk under that literal PATH, `bats -f shed` was 2/4 red
  # (`ABOVE` unreachable at any ceiling; "smoke SKIPPED" never emitted); absolute resolution is 4/4.
  # Resolved INSIDE the function, never from a file-level global: tests/ship-land.bats extracts this
  # function with sed and runs it standalone, so a dependency on state set elsewhere in the file
  # would make it behave differently under test than in production. The seam is honoured VERBATIM
  # (including empty) — the only way to exercise the unreadable arm on a host that HAS the binary.
  # (Class = memory path-resolved-dependency-in-daemon-code; first landed as e6de2e15.)
  local sysctl_bin
  if [ -n "${CC_GATE_SYSCTL+set}" ]; then sysctl_bin="$CC_GATE_SYSCTL"
  elif [ -x /usr/sbin/sysctl ];      then sysctl_bin=/usr/sbin/sysctl
  else                                    sysctl_bin="$(command -v sysctl 2>/dev/null || true)"
  fi
  [ -n "$sysctl_bin" ] || return 1                            # no sensor at all ⇒ fail OPEN

  # The ceiling is resolved AFTER the sensor because the DERIVED default needs hw.ncpu from that
  # same binary — one resolution, so a host where sysctl is unreachable cannot end up with a
  # half-derived ceiling. An explicit value never consults hw.ncpu at all.
  max="${CC_GATE_MAX_LOAD:-}"
  if [ -z "$max" ]; then
    percore="${CC_GATE_MAX_LOAD_PER_CORE:-8}"
    # These two `case`s were written MULTI-LINE to work around a permission-gate-lint defect, and the
    # DEFECT IS NOW FIXED (2026-08-12, backlog 3709b1649792) — so the constraint is retired and this
    # note is history, kept because the scar explains a real land-block. The lint tracks an if/case
    # block stack to decide which condition ENCLOSES a refusal, and it used to push on a line-initial
    # `case` without the trailing-`esac` check it already applied to a one-line `if … fi`. A
    # single-line `case … esac` therefore pushed and never popped, and the leak shifted the MAXENC
    # window for refusals far LATER in the file: two one-liners here made the `no suites matched`
    # guard of run_corpus() (line ~890) read as a newly-added unbounded gate, 17 → 18 against the
    # ratchet, in a function this change never touched. It was position-dependent — injecting a
    # one-liner at TOP LEVEL did NOT reproduce it, so the obvious probe read clean and looked like a
    # refutation. permission-gate-lint.sh now skips the push on a trailing `esac`, and
    # tests/permission-gate-lint.bats case 25 holds it there by mutation. Either spelling is safe;
    # multi-line is kept here only because these two are already written that way.
    case "$percore" in
      ''|*[!0-9.]*) percore=8 ;;                               # non-numeric factor ⇒ the default
    esac
    ncpu="$("$sysctl_bin" -n hw.ncpu 2>/dev/null || true)"
    case "${ncpu:-}" in
      ''|*[!0-9]*) ncpu=1 ;;                                   # unreadable core count ⇒ 1 core,
    esac
    # Integral results print as integers so the shed message reads "80", not "80.0000"; %.4f is the
    # fractional fallback. NEVER %g — it renders ≥1e6 in scientific notation, which the numeric
    # guard below would reject as non-numeric and fail OPEN on a ceiling that was merely large.
    max="$(awk -v n="$ncpu" -v p="$percore" \
      'BEGIN{v=n*p; if (v==int(v)) printf "%d", v; else printf "%.4f", v}')"  # the SAFE direction:
  fi                                                          # a low ceiling sheds, never runs wild
  [[ "$max" = "0" || "$max" = "off" ]] && return 1            # kill switch: never shed
  case "$max" in ''|*[!0-9.]*) return 1 ;; esac               # non-numeric ceiling ⇒ fail OPEN

  load="$("$sysctl_bin" -n vm.loadavg 2>/dev/null | awk '{print $2}')"
  case "${load:-}" in ''|*[!0-9.]*) return 1 ;; esac          # unreadable sensor ⇒ fail OPEN
  # Publish the raw inputs so the SHED MESSAGE can name them. A skip that cannot say what load it
  # saw, against what ceiling, is unauditable after the fact — and this whole defect survived a
  # year of lands precisely because nothing downstream carried the numbers.
  SHED_LOAD="$load"; SHED_CEILING="$max"
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
  # NO TRAP HERE ANY MORE — teardown is the FIRST thing _land_exit_trap does, and the signal
  # handler calls it too. This used to install `trap gate_home_teardown EXIT` and its own comment
  # required any second EXIT trap to compose with it; P4 needed one (the failure inbox + the
  # in-flight marker must be discharged on EVERY exit, not only a gated one), and two `trap … EXIT`
  # lines in one process do not compose — the later one silently REPLACES the earlier. So there is
  # exactly one EXIT handler, installed at dispatch, and it runs teardown first. The old comment's
  # other half still binds and is now implemented there: INT/TERM are trapped, but the handler
  # re-raises the death as `128 + signum` rather than swallowing it, so Ctrl-C still means stop.
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
  # CLAUDE_CONFIG_DIR RIDES WITH $HOME, AND WITHOUT IT THE ISOLATION HAS A HOLE IT CANNOT SEE.
  # Overriding HOME is the whole mechanism above, and it has NO purchase on this variable: it is an
  # ABSOLUTE path, so a child resolving `${CLAUDE_CONFIG_DIR:-$HOME/.claude}` walks straight past
  # the clone to whatever the operator's session exported. That is not the bounded, honest gap
  # gate_home_setup documents ("writes THROUGH a symlinked entry are not contained") — a symlinked
  # entry is still reached via $HOME, so isolation at least DECIDES it. This routes around $HOME as
  # a mechanism entirely, and it is live on this desk: the launcher `bin/claude-kimi` exports it and
  # every session here runs with it set to a per-account dir (e.g. ~/.claude-quaternary), which the
  # clone list does NOT clone — so the gate clones the `.claude` its children do not read and leaves
  # unprotected the one they do. Measured 2026-08-21: 79 tools under bin/ scripts/ hooks/ read it.
  #
  # SET, NOT UNSET, and that is measured too. For the 65 readers spelling `${CLAUDE_CONFIG_DIR:-
  # $HOME/.claude}` the two are identical once HOME is the clone. They diverge for the 6 that spell
  # `${CLAUDE_CONFIG_DIR:-}` (scripts/handoff-fire.sh among them) and the 3 bare `$CLAUDE_CONFIG_DIR`
  # reads: unsetting hands those an EMPTY string, i.e. paths rooted at `/` — a NEW failure mode the
  # gate itself would introduce. Setting it gives all three classes one contained answer.
  #
  # FAIL-OPEN IS PRESERVED IN BOTH DIRECTIONS. This rides the same `-n "$GATE_HOME"` test as HOME, so
  # a gate that fell open re-roots nothing. And if `.claude` is not in the clone list, `$GATE_HOME/
  # .claude` is the symlink step 1 farmed to the real one — the child then reaches exactly what it
  # reaches today, never an ABSENT path (the one outcome gate_home_setup must never cause).
  [[ -n "${GATE_HOME:-}" ]] && homeenv=(HOME="$GATE_HOME" CLAUDE_CONFIG_DIR="$GATE_HOME/.claude")
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
  # THE P0 MEASUREMENT CARRIERS SCRUB HERE TOO, and they are the sharpest members of this list
  # because they are not tuning at all — they are STATE this land is mid-way through accumulating.
  # meas_export() hands them to the locked re-exec, so once a land takes the in-lock path every
  # suite it then smokes inherits a non-zero round count and a running clock. A fixture pipeline
  # starts counting from the OUTER land's total: tests/land-gate-cas.bats's stale-round case asserts
  # `gate_rounds:2` and got 3, i.e. a suite that is green everywhere else goes red as a function of
  # whether a sibling happened to move the trunk during the land that ran it (reproduced exactly:
  # `SHIP_LAND_MEAS_ROUNDS=1 bats -f 'P0 exit 42 attests' …` fails on the same line the land did).
  # Scrubbed at the gate rather than only in the two suites' setups, because the poison is available
  # to EVERY suite this function runs and a per-suite fix is a list someone must remember to join
  # (memory: enforcement-must-live-at-the-chokepoint). SHIP_LAND_T0 rides along: it carries the
  # end-to-end clock, so an inherited one makes a fixture's `total_s` the outer land's age.
  #
  # 🚨 NOTHING MAY COME BETWEEN THE `\` BELOW AND `env` — NOT EVEN A COMMENT. A comment line after a
  # line-continuation ENDS the continuation: `${pre[@]+…}` then runs as its own command and `env …
  # bats` as another, so the timeout/nice prefix silently stops wrapping the suite. Measured while
  # writing the scrub above: the comment block sat between the two lines, and the bounded-smoke
  # cases went red with `smoke green — 1 direct suite(s) in 120s` over a fixture that hangs for 120s
  # under a 3s budget. The bound had not loosened; it was not there at all — and the only reason
  # this was caught is that tests/ship-land.bats pins the wall bound in both directions.
  ${pre[@]+"${pre[@]}"} \
  env -u SHIP_LAND_GATE_ROUNDS -u SHIP_LAND_VERIFY_RETRIES -u SHIP_LAND_GATE_SCOPE \
      -u LAND_LOCK_WAIT -u LAND_LOCK_TTL \
      -u SHIP_LAND_LANE -u SHIP_LAND_SMOKE_BUDGET_S -u SHIP_LAND_TIMEOUT_BIN \
      -u SHIP_LAND_T0 -u SHIP_LAND_MEAS_ROUNDS -u SHIP_LAND_MEAS_GATE_S \
      -u SHIP_LAND_MEAS_ARMS_S -u SHIP_LAND_MEAS_STATICS_S \
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
  local -a redf=()          # WHICH suites named a failure — §9 item 4's "log the failing suite name"
  echo "→ gate[v1]: bats tests/ — full corpus, one process per suite (SHIP_LAND_LANE kill switch)" >&2
  for f in tests/*.bats; do
    [[ -e "$f" ]] || continue
    n=$(( n + 1 ))
    srv=0; run_scoped_suite "$f" "$direct" || srv=$?
    case "$srv" in
      0) ;;
      2) killed=$(( killed + 1 )) ;;
      *) red=$(( red + 1 )); redf+=("$f") ;;
    esac
  done
  SELECTED_N="$n"
  if [[ "$n" -eq 0 ]]; then
    echo "✗ gate[v1]: no suites matched tests/*.bats — refusing to claim green on an empty corpus" >&2
    gate_red bats-empty-corpus; return 1
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
    # One entry per failing suite, not a count: "$red of $n failed" is exactly the shape §9 could
    # not act on. The cap in gate_red bounds a mass failure and says so rather than trimming quietly.
    for f in "${redf[@]}"; do gate_red bats "$f"; done
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
  local range="$1" direct own budget start f n=0 red=0 cut=0 srv own_red=0
  local -a redf=()          # the direct suites that named a failure — attested, not just counted
  # ---- P0 §3: `none` WAS FIVE CAUSES WEARING ONE TOKEN ------------------------------------------
  # (§2.B.) 83% of lands execute no test of their own diff, and until now the ledger could not say
  # WHY for any of them — a load-shed land, a lint-only land, a land whose selector was missing, and
  # a land whose gate died before the smoke all attested the identical `none`. So the single largest
  # coverage fact about this pipeline was unbreakdownable, and "83% ungated" could not be argued
  # about: it pooled a deliberate cheap path with an instrument outage. Each cause is now its own
  # token, all sharing the `none-` prefix so a reader can still ask the pooled question in one match
  # (memory: sensor-default-off-makes-blindness-the-shipping-path — one value serving two questions
  # is how a blind sensor becomes the shipping path).
  #
  #   none-unreached   a statics/ratchet arm went red first — the gate never reached the smoke
  #   none-nosuites    the repo has no tests/*.bats at all
  #   none-locked      the in-lock fallback lane: bats is structurally banned under the mutex
  #   none-precheck    --precheck scope (never reaches land.log; the precheck writes no row)
  #   none-noselector  gate-select.sh missing / not executable
  #   none-undecided   the selector answered FULL, its fail-closed "I cannot decide"
  #   none-nodirect    0 direct suites map to this range after the host-suite filter (lint-only)
  #
  # `skipped` (load-shed) already had its own token and keeps it — it was never part of the
  # conflation, and re-spelling it would break every reader for no gain.
  SMOKE_STATE="none-nosuites"; SMOKE_N=0; SMOKE_S=0; SMOKE_DEADLINE=""
  ls tests/*.bats >/dev/null 2>&1 || return 0

  # STRUCTURAL: nothing heavy may EVER run under the land-lock. Not a policy an author can forget —
  # the check lives here, at the only place that could start a suite. v1's in-lock full gate is the
  # 3h36m lock holder and the multi-day jam; the lock exists for the CAS race window alone.
  if [[ "$IN_LAND_LOCK" = "1" ]]; then
    SMOKE_STATE="none-locked"
    echo "→ gate[locked]: statics + ratchets only — no bats inside the land-lock (v2 invariant)." >&2
    return 0
  fi
  # The precheck's declared scope (see the header): statics + all fifteen ratchet arms, no smoke.
  # Stated as its own branch and its own message so a precheck can never be mistaken, in a log or
  # by a reader, for a land that happened to select zero suites. It now also has its own TOKEN — the
  # comment used to say "SMOKE_STATE stays none for both and only this line distinguishes them",
  # i.e. the distinction lived in a stderr line nobody stores. A precheck writes no land.log row, so
  # the token is unreachable from the store; it is set anyway so the two states differ in the
  # variable as well as in the message, which is what a later reader will actually check.
  if [[ "$GATE_PRECHECK" = "1" ]]; then
    SMOKE_STATE="none-precheck"
    echo "→ gate[precheck]: statics + ratchets only — the smoke phase is the land's, not the precheck's." >&2
    return 0
  fi

  if [[ ! -x "$GATE_SELECT" ]]; then
    # v1 read this as FULL (fail-closed toward a 40-minute corpus). In v2 "fail-closed toward more
    # proof" IS the amplifier: the selector is missing exactly on the live-symlink path where a
    # brand-new tracked file has no symlink yet, i.e. on the busiest boxes. No selection ⇒ no
    # smoke; the verifier still proves the tree, and the land is not punished for a deploy gap.
    SMOKE_STATE="none-noselector"
    echo "⚠ gate: selector '$GATE_SELECT' missing/not executable — no smoke this land; the post-land verifier proves this tree." >&2
    return 0
  fi
  # THE SELECTION HAS TWO POPULATIONS AND EVERY CONSUMER BELOW USED TO READ IT AS ONE (backlog
  # fb178d6d8d14). UNION SCOPE hands the selector a SECOND range on a re-round, so `direct` is
  # {suites this diff maps to} ∪ {suites the SIBLING delta maps to}. Running both is right and is
  # not in question — the composed tree is what we are about to push. What was wrong is that both
  # of the things that then JUDGE a failure ("intermittence in code you are landing is a finding,
  # not a flake"; "this is a VERDICT about your diff … fix it, do not retry unchanged") are clauses
  # whose truth has a POPULATION, and it is the own-range one. The row that filed this measured the
  # consequence landing 75df8db2c884: round 2 selected 13 suites including one with zero references
  # to either changed file, the lander was told to go fix it, and the same failure was ALREADY an
  # open item filed by the post-land verifier against a sibling's commit.
  #
  # The row's own prescribed remedy — "assert selected-suites is a SUBSET of gate-select over the
  # attested base..head; a suite outside that set must never be able to set the exit code" — is
  # REFUSED here, and deliberately: that deletes union scope, which is the only thing covering the
  # composed tree's sole novelty. The defect is attribution, not selection. So: run the union,
  # judge with the own set.
  #
  # ORDER MATTERS — the own-range call goes FIRST because tests/land-gate-cas.bats reads the LAST
  # selector invocation to assert the re-round carried two ranges. Skipped entirely when there is
  # no union (round 1, ~70% of lands), where own IS direct by construction and this costs nothing.
  own=""
  if [[ -n "$EXTRA_RANGE" ]]; then
    own="$("$GATE_SELECT" --direct "$range" 2>/dev/null || true)"
  fi
  direct="$("$GATE_SELECT" --direct "$range" ${EXTRA_RANGE:+"$EXTRA_RANGE"} 2>/dev/null || true)"
  if [[ "$direct" = "FULL" ]]; then
    # FULL is the selector's own fail-closed answer ("I could not decide"). It can no longer mean
    # "run everything", so its honest v2 reading is "this selection is untrustworthy" ⇒ no smoke.
    SMOKE_STATE="none-undecided"
    echo "⚠ gate: selector answered FULL (its fail-closed 'cannot decide') — no direct-suite smoke this land; the verifier proves the tree." >&2
    return 0
  fi
  direct="$(printf '%s\n' "$direct" | grep -v '^[[:space:]]*$' || true)"
  # BEFORE the emptiness check on purpose: a land whose every direct suite is a host suite is a
  # lint-only land as far as the smoke is concerned, and must take that branch (and its zero cost)
  # rather than a separate one.
  direct="$(filter_host_suites "$direct" | grep -v '^[[:space:]]*$' || true)"
  # OWN resolves to the SAME list as `direct` in both of the cases where the partition is unknown or
  # absent, so every judgment below keeps its present behaviour unless a union genuinely added a
  # suite this diff does not map to. FAIL-CLOSED both ways: no union ⇒ everything is ours (true by
  # construction); the own-range selector answering FULL ("I cannot decide") ⇒ everything is ours
  # (the safe direction — an undecided selector must never be read as "none of this is yours",
  # which would exonerate the whole smoke). Normalised identically, or the membership test below
  # would compare a filtered path against an unfiltered one and silently miss.
  if [[ -z "$EXTRA_RANGE" || "$own" = "FULL" ]]; then
    own="$direct"
  else
    own="$(printf '%s\n' "$own" | grep -v '^[[:space:]]*$' || true)"
    own="$(filter_host_suites "$own" | grep -v '^[[:space:]]*$' || true)"
  fi
  if [[ -z "$direct" ]]; then
    SMOKE_STATE="none-nodirect"
    echo "→ gate: smoke — 0 direct suite(s) map to this range (lint-only land)." >&2
    return 0
  fi

  if load_above_ceiling; then
    SMOKE_STATE="skipped"
    # LOUD, and it names the CONSEQUENCE rather than only the cause. The old wording ended "the
    # post-land verifier proves this tree", which reads as a completed proof; the verifier is a
    # BACKSTOP that trails trunk (measured 111 commits / ~20 h behind on 2026-08-08), so at the
    # moment of landing nothing has executed this diff. A skip that sounds like a hand-off is how
    # 352 ungated lands went unnoticed — the numbers are printed for the same reason.
    echo "⏭ gate: smoke SKIPPED — this land is behaviorally UNGATED: statics passed, but NO suite of this diff ran (1-min load ${SHED_LOAD:-?} ≥ ceiling ${SHED_CEILING:-?}). Shedding is a SKIP, never a wait (waiting is what starved five gates below their own ceiling). The post-land verifier is the only remaining net and it trails trunk by hours, so a suite this diff breaks can sit RED on trunk until it catches up. Override: CC_GATE_MAX_LOAD=0." >&2
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
    # `own`, NOT `direct`: run_scoped_suite's carve-out reads this list as "code you are landing",
    # and on a re-round `direct` also holds the sibling delta's suites, which are not that.
    srv=0; run_scoped_suite "$f" "$own" || srv=$?
    case "$srv" in
      0) ;;
      2) cut=1 ;;                                        # cut twice / bound fired ⇒ NO verdict
      # Membership by `case` over a newline-fenced string, NOT `printf | grep -qxF`: this file runs
      # under `set -o pipefail`, where a producer piped into an early-exiting `grep -q` can be
      # promoted to 141 on a MATCH (the ratchet ~800 lines below is the repo's own scar for it).
      # Fork-free, and it cannot report the opposite of what it found.
      *) red=$(( red + 1 )); redf+=("$f")                # a named `not ok` ⇒ a verdict
         case $'\n'"$own"$'\n' in *$'\n'"$f"$'\n'*) own_red=$(( own_red + 1 )) ;; esac ;;
    esac
  done <<< "$direct"
  SMOKE_S=$(( $(date +%s) - start ))
  SMOKE_N="$n"
  SMOKE_DEADLINE=""
  gate_home_teardown

  if [[ "$red" -gt 0 ]]; then
    SMOKE_STATE="red"
    # ATTEST THE POPULATION, not just the suite. `smoke:<file>` said which suite; it could not say
    # whether that suite was reachable from this diff at all, so land.log could not distinguish
    # "the lander broke a test" from "a sibling landed a red mid-gate and the next lander wore it".
    # A distinct arm makes the two separable in gate-red-census.sh, which counts arms as MENTIONS
    # rather than a partition, so a new one costs its readers nothing.
    for f in "${redf[@]}"; do
      case $'\n'"$own"$'\n' in
        *$'\n'"$f"$'\n'*) gate_red smoke "$f" ;;
        *)                gate_red smoke-sibling "$f" ;;
      esac
    done
    if [[ "$own_red" -gt 0 ]]; then
      echo "✗ gate: smoke RED — $red of $n direct suite(s) named a failure ($own_red mapped to YOUR diff). This is a VERDICT about your diff (O(diff), reproducible): fix it, do not retry unchanged." >&2
    else
      # THE WHOLE RED CAME FROM UNION SCOPE. Still blocks — we are about to push onto a composed
      # tree that has a named failure in it, and fail-closed is the right direction for a gate —
      # but the old sentence made a claim it had no evidence for and prescribed an action the
      # lander cannot take. "Fix it, do not retry unchanged" pointed at a subsystem this diff never
      # touched; on a box whose trunk is persistently not-green that converts every mid-gate
      # sibling landing into a false conviction of the next lander, and the measured instance was
      # already an OPEN item filed by the post-land verifier against the sibling's commit.
      echo "✗ gate: smoke RED — $red of $n direct suite(s) named a failure, and NONE of them map to your diff: they were selected by UNION SCOPE (the trunk delta \"$EXTRA_RANGE\" a sibling landed while we gated). This is NOT a verdict about your code — do not go edit it." >&2
      echo "  The composed tree is red, so the land is refused; the failure belongs to that sibling delta and is very likely already filed by the post-land verifier. Check there before touching anything, and re-run /ship once trunk is green." >&2
    fi
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
  # THREE LEGS, cut separately so no one of them can hide another's regression. Leg 0 comes FIRST
  # because the other two only ever run on lines it has already admitted:
  #
  # LEG 0 — THE GRAMMAR. TAP spells a result `not ok <N> <desc>`, and the <N> is the ONLY thing
  # separating a RESULT from arbitrary text that opens with those four bytes. Arbitrary text is
  # ROUTINE in this stream: gate_bats captures 2>&1, so an unprefixed stderr write splices straight
  # in (hooks/session-register.sh:347 names one such injector by name), and a suite killed mid-write
  # truncates a line wherever the buffer happened to end. Measured on /usr/bin/grep (BSD
  # 2.6.0-FreeBSD) AND ugrep 7.5.0 (the operator's own interactive PATH), four shapes count 1 under
  # the old `^not ok` and 0 here:
  #     `not ok` · `not ok3 squashed` · `not okay then` · `not okcorpus: 3 suites`
  #   -E  the <N> needs a repeat operator, so this cannot stay a BRE.
  #   -a  the count must not change with WHICH grep is on PATH — ugrep reads a NUL-carrying TAP as
  #       EMPTY without it, which would resurrect the same disagreement from the other side.
  # SAME SPELLING as scripts/postland-verify.sh TAP_NOTOK_RE (C30) and scripts/deploy-live.sh;
  # tests/tap-grammar-parity.bats pins all four equal. Deliberately NOT sourced from a shared lib:
  # ~/.claude is per-file symlinks, so a NEW lib file is absent from the live layer until
  # deploy-live converges, and a `[ -f lib ] && . lib` guard would silently fall back to the loose
  # grammar on exactly the boxes that run a land. The `sig=` line in run_scoped_suite stays loose on
  # purpose: it is a human-readable signature for the flake ledger, never a discriminator, and a
  # torn line is honest evidence there.
  local log="$1" known="${2:-0}" f="${3:-the suite}" n plan
  n="$(grep -acE '^not ok [0-9]+' "$log" 2>/dev/null || true)"; n="${n:-0}"
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

# own_run <ARM> <CC_VAR> <own-set> <cmd…> → the lint's rc, with the own-set handed over CORRECTLY.
#
# WHAT THIS FIXES (land-architecture-100p §5 P2). Every ratchet arm below carried the same two
# lines — `local own=""` guarded by `[[ "${SHIP_LAND_<ARM>_OWN_SCOPE:-on}" != "off" ]]`, then an
# unconditional `CC_<ARM>_OWN="$own" "$LINT"` — and the pair does the OPPOSITE of what all
# thirteen of their comments say. The lints read THREE states, and the caller could only ever
# produce two of them:
#     UNSET          nobody scoped ⇒ strict, the whole tree may block
#     SET-BUT-EMPTY  a caller scoped and owns nothing here ⇒ nothing may block
#     SET            only these files may block
# Setting the documented kill switch (`SHIP_LAND_HERM_OWN_SCOPE=off`, whose own comment reads
# "restores whole-tree blocking") left `own` empty and STILL exported the variable — so the lint
# saw SET-BUT-EMPTY and blocked on NOTHING. The escape hatch for a leaking arm silently DISABLED
# that arm instead of tightening it, which is strictly worse than having no switch: an operator
# reaching for it in an incident gets a green gate and believes they got a stricter one (memory:
# prescribed-remedy-worse-than-the-bug, and guard-proxy-fails-in-both-directions).
#
# Routing every arm through one function also retires thirteen copies of the switch read. The
# switch is now consulted in exactly ONE place, so an arm added later cannot get it wrong by
# copying a neighbour — which is how all thirteen came to share the defect. `${!sw:-on}` is
# indirect expansion, bash 3.2 safe (verified on 3.2.57).
own_run() {
  local sw="SHIP_LAND_${1}_OWN_SCOPE" var="$2" val="$3"; shift 3
  if [[ "${!sw:-on}" = "off" ]]; then
    # STRICT, and it must be the ABSENCE of the variable rather than an empty one — that is the
    # whole distinction above. The subshell is what makes `unset` local to this call.
    ( unset "$var"; "$@" )
  else
    ( export "$var=$val"; "$@" )
  fi
}

# The .bats shellcheck ratchet's NON-VERDICT arm, factored out because BOTH of its legs (--selftest
# and the scan) reach it and a copy-paste pair is how one of them ends up saying something else.
# GATE_KILLED (⇒ exit 9, retryable) rather than gate_red (⇒ exit 6): exit 2 is the lint saying it
# could not run, which is not a claim about the lander's tree.
# shellcheck disable=SC2329  # invoked from run_gate's bats-shellcheck arm below.
bats_sc_nonverdict() {
  echo "⛔ gate: bats-shellcheck-lint could not RUN (exit 2) — a NON-VERDICT, not a claim about your tree." >&2
  echo "  The usual cause is that shellcheck is not installed on this host. Landing anyway would" >&2
  echo "  leave every .bats suite unlinted and SAY NOTHING, which is what this arm exists to stop." >&2
  echo "  Install shellcheck and re-land." >&2
  GATE_KILLED=1
}

# THE GENERIC NON-VERDICT ARM. Every ratchet lint here answers with THREE codes — 0 clean, 1 findings,
# 2 I-COULD-NOT-RUN — but nine of the sixteen arms consumed them with `if ! own_run …; then gate_red x`,
# which collapses 2 into 1 and reports "your tree is bad" for a lint that never rendered a verdict.
# Measured 2026-08-13 on this file: 9 collapse, 7 discriminate. GATE_KILLED yields exit 9 (retryable,
# "re-run when the box is quieter"); gate_red yields exit 6 (author-fixable) and sends someone to fix a
# file the lint may never even have read.
#
# Factored rather than copied nine times for the reason stated above bats_sc_nonverdict: a copy-paste
# pair is how one of them ends up saying something else. That helper stays as-is — its text names an
# install step this generic one cannot know.
# $3 exists because ONE could-not-run does not arrive as a 2: the dead-assertion arm's lint is a
# python program, and a python program that dies before its own handler runs exits 1 (uncaught
# exception) or 127 (no interpreter). Printing a hardcoded "(exit 2)" over a 127 would send the
# reader hunting for a usage error the lint never reported. Default stays 2 — every other caller is
# consuming a lint whose could-not-run IS a 2, and none of them had to change.
# shellcheck disable=SC2329  # invoked from run_gate's arms below.
# lint_own_scope <lint> <range> — the own-set for a lint that can NAME the population it judges.
# Echoes newline-delimited repo-relative paths from this land's diff; rc 2 ⇒ the lint could not say.
#
# THE SEAM THIS CLOSES (backlog 0be0bd2c0b65, then 5fc8ff411a7c). Eight arms below used to build
# their own-set from a pathspec RESTATED here — `-- 'install.sh' 'scripts/*'` for permission-gate,
# `-- 'bin/*' 'hooks/*' 'scripts/*'` for tsv-pad, and one apiece for utc-stamp, pipefail-sigpipe,
# self-path, pane-spawn, unattended-path and chromium-bundle — each with a comment telling the next
# author to widen it in the same diff if the lint's population ever reached another directory.
# Nothing executes a comment. Each pair of populations could drift apart, and the drift is silent in
# the dangerous direction: a land that adds a violation under a directory the stale pathspec misses
# builds an own-set WITHOUT that file, so the finding degrades to advisory and lands. Deriving the
# pathspec from the lint makes them identical by construction rather than by discipline
# (memory: resident-policy-must-not-restate-perishable-facts).
#
# AN ENV SEAM WAS NEVER THE ONLY WAY THESE COME APART, and that is why the six arms held back from
# the first pass were wrong to hold back. The first two lints could move their population at RUNTIME
# (CC_PERMGATE_SET / CC_TSVPAD_DIRS), which made the risk easy to see; the other six can move theirs
# only by a CODE edit to the lint's own scan set. Same silent direction, no seam required — and two
# of them had ALREADY drifted when this landed: the pipefail pathspec carried no `*.bats` though the
# lint judges `*.bats` anywhere, and the unattended pathspec had to have `tests/*` grafted on by hand
# after a bare `md5` in cc-queue.bats C12 passed vacuously on every scheduled run. A restatement that
# has already failed twice is not defended by being hard to move.
#
# rc 2 IS A NON-VERDICT AND MUST STAY ONE. A lint that cannot answer `--print-scope` (missing, or an
# older copy that does not know the flag and exits 2 with empty stdout) must NOT silently yield an
# EMPTY own-set — that is the exact failure this helper exists to prevent, arriving by a new route:
# an empty own-set is the legitimate spelling of "this land touches nothing I judge", so it blocks on
# nothing and says nothing. Callers route rc 2 into arm_nonverdict (⇒ GATE_KILLED ⇒ exit 9,
# retryable), never into gate_red — the lint made no claim about the lander's tree.
#
# A land that legitimately touches none of the lint's population still returns rc 0 with EMPTY
# output, which is the SET-BUT-EMPTY state own_run already carries. Empty-with-rc-0 and
# empty-with-rc-2 are different answers here, exactly as they are for the lints themselves.
# shellcheck disable=SC2329  # invoked from run_gate's eight own-scoped ratchet arms below.
lint_own_scope() {  # $1=lint path · $2=diff range
  local lint="$1" range="$2" line
  local spec=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && spec+=("$line")
  done < <("$lint" --print-scope 2>/dev/null)
  # bash 3.2 errors on "${arr[@]}" for an EMPTY array under `set -u`, so this test is not cosmetic —
  # it is also the rc-2 gate. Same guard, same reason, as collect_actuation in permission-gate-lint.
  [[ "${#spec[@]}" -gt 0 ]] || return 2
  git diff --name-only "$range" -- "${spec[@]}" 2>/dev/null || return 2
}

arm_nonverdict() {  # $1=lint label · $2=optional extra hint line · $3=optional exit code (default 2)
  echo "⛔ gate: $1 could not RUN (exit ${3:-2}) — a NON-VERDICT, not a claim about your tree." >&2
  echo "  Nothing is wrong with the files named above (if any) — the lint never reached a verdict." >&2
  [ -n "${2:-}" ] && echo "  $2" >&2
  echo "  Re-run /ship when the box is quieter." >&2
  GATE_KILLED=1
}

run_gate() {  # $1=range → 0 green / 1 red
  local range="$1" p rc=0 HERM_LINT SELFPATH_LINT _arm_rc=0
  # GATE_EFFECTIVE_FULL is pinned at 0: a land makes no full-suite claim in EITHER lane, so
  # stamp_gate_green self-noops and the verifier stays the marker's only writer (§4.2).
  # GATE_RED_WHY resets WITH GATE_RED, never separately: the optimistic loop re-enters run_gate on
  # the exit-42 stale-gate round, and a why that outlived its flag would attest round 1's arm against
  # round 2's verdict — attribution that is worse than none, because it reads as evidence.
  GATE_EFFECTIVE_FULL=0; SELECTED_N=-1; GATE_RED=0; GATE_KILLED=0; GATE_RED_WHY=""
  # ---- P0: open the round's measurement ----------------------------------------------------
  # Incremented HERE rather than in the optimistic loop, because the loop is not the only thing that
  # re-gates: the in-lock fallback gates once more in a different process, and the post-drop retry
  # loop gates again inside the lock. `gate_rounds` must count what actually RAN, so it counts
  # entries to this function and carries across the locked re-exec like SMOKE_* does.
  GATE_T0="$(date +%s)"; GATE_T_STATICS_END=""; GATE_T_ARMS_END=""
  MEAS_ROUNDS=$(( MEAS_ROUNDS + 1 ))
  # THE DEFAULT SMOKE CAUSE IS "the gate never got there", and it must be set at the TOP. Fifteen
  # ratchet arms `return 1` before the smoke phase, and every one of them used to attest the same
  # `smoke:"none"` a lint-only land attests — 305 of the 735 `none` rows in the live store are
  # exit-6 rows, i.e. lands whose gate died before the smoke could have a cause at all. That is a
  # sixth cause the audit's five did not name, and it is the second largest.
  SMOKE_STATE="none-unreached"
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

  # P3: the per-file statics memo. shellcheck / `bash -n` / py_compile are pure functions of ONE
  # file's bytes, so a verdict keyed on the blob sha (plus the checker's own version — see
  # gate-memo.sh's salt) is exact, not approximate. On a re-round only the sibling's files are
  # unknown; ours were proven a round ago and are byte-identical.
  #
  # SUBSETTING IS SOUND HERE and that is a property of the invocation, not an assumption: this gate
  # calls shellcheck WITHOUT -x, so it follows no `source` and each file is judged in isolation —
  # running it over half the set gives every file the same verdict as running it over all of them.
  # (The repo's `# shellcheck source=/dev/null` directives are SC1091 suppressions, not follows.)
  # If -x is ever added, this memo must key on the sourced files too; tests/land-gate-memo.bats
  # states that dependency.
  memo_init || true
  local sc_todo=() bn_todo=() py_todo=()
  if [[ ${#shellfiles[@]} -gt 0 ]]; then
    while IFS= read -r p; do [[ -n "$p" ]] && sc_todo+=("$p"); done < <(memo_partition shellcheck ${shellfiles[@]+"${shellfiles[@]}"})
    while IFS= read -r p; do [[ -n "$p" ]] && bn_todo+=("$p"); done < <(memo_partition bash-n ${shellfiles[@]+"${shellfiles[@]}"})
  fi
  if [[ ${#pyfiles[@]} -gt 0 ]]; then
    while IFS= read -r p; do [[ -n "$p" ]] && py_todo+=("$p"); done < <(memo_partition py_compile ${pyfiles[@]+"${pyfiles[@]}"})
  fi

  if [[ ${#shellfiles[@]} -gt 0 ]]; then
    echo "→ gate: shellcheck + bash -n on ${#shellfiles[@]} shell file(s) (${#sc_todo[@]} unproven / ${#bn_todo[@]} unparsed — the rest carried by blob sha)" >&2
    if [[ ${#sc_todo[@]} -gt 0 ]] && ! command -v shellcheck >/dev/null 2>&1; then
      # A MISSING checker is not a claim about this tree. Unguarded, `shellcheck` exits 127 and the
      # else-arm below files gate_red shellcheck — so a box without the binary is told its code is
      # RED, and told it identically whether the code is spotless or filthy. bats_sc_nonverdict()
      # already states this rule for the .bats ratchet ~60 lines up — "the usual cause is that the
      # checker is not installed on this host" — and this arm is the one that never got it. (That
      # sentence is paraphrased on purpose: a comment line BEGINNING with the checker's own name
      # parses as a directive, SC1073, and aborts the lint for the whole file.)
      # MEASURED 2026-08-12: GitHub's macos-latest image ships no shellcheck, and
      # tests/gate-precheck.bats was 6-ok / 7-notok there on every hermetic run because of it. The
      # six "passes" were vacuous — they assert exit 6 naming `arm(s): shellcheck`, which is exactly
      # what a missing binary produces, so off-box that suite has never once exercised shellcheck.
      # GATE_KILLED ⇒ the retryable 9, which is what keeps could-not-run apart from is-wrong.
      echo "⛔ gate: shellcheck is NOT INSTALLED — a NON-VERDICT, not a claim about your tree." >&2
      echo "  ${#sc_todo[@]} shell file(s) went unjudged. Install shellcheck and re-land." >&2
      GATE_KILLED=1; rc=1
    elif [[ ${#sc_todo[@]} -gt 0 ]]; then
      # No subject: shellcheck judges the whole set in one call, so naming one file would be a guess.
      if shellcheck "${sc_todo[@]}" >&2; then
        # Recorded ONLY on a whole-set green. A red says nothing about WHICH file was clean, so
        # nothing is recorded and every one of them re-runs next round — the safe direction, and
        # the reason a red is never replayed from cache.
        for p in "${sc_todo[@]}"; do memo_file_record shellcheck "$p"; done
      else
        # The trailing `;` on the next line is LOAD-BEARING, not style: tests/ship-land.bats builds
        # its attest-red mutant by sed'ing that exact literal, and asserts the anchor matches
        # EXACTLY ONCE. So reformatting the line disarms the mutant — and restating the literal
        # anywhere else in this file, including in a comment like this one, breaks the count the
        # other way. Both failure modes were hit while landing P3.
        echo "✗ gate: shellcheck RED" >&2; rc=1; gate_red shellcheck;
      fi
    fi
    for p in ${bn_todo[@]+"${bn_todo[@]}"}; do
      if bash -n "$p" 2>&1 >&2; then memo_file_record bash-n "$p"
      else echo "✗ gate: bash -n RED: $p" >&2; rc=1; gate_red bash-n "$p"; fi
    done
  fi
  if [[ ${#pyfiles[@]} -gt 0 ]]; then
    echo "→ gate: py_compile on ${#pyfiles[@]} python file(s) (${#py_todo[@]} unproven; incl. extensionless-by-shebang)" >&2
    if [[ ${#py_todo[@]} -gt 0 ]]; then
      if python3 -m py_compile "${py_todo[@]}" >&2; then
        for p in "${py_todo[@]}"; do memo_file_record py_compile "$p"; done
      else
        echo "✗ gate: py_compile RED" >&2; rc=1; gate_red py_compile
      fi
    fi
  fi
  memo_count $(( ${#shellfiles[@]} * 2 + ${#pyfiles[@]} - ${#sc_todo[@]} - ${#bn_todo[@]} - ${#py_todo[@]} )) \
             $(( ${#sc_todo[@]} + ${#bn_todo[@]} + ${#py_todo[@]} ))
  memo_summary
  # P0 phase boundary: everything above is the STATICS (the ~2% P3's memo already retired);
  # everything below, to the smoke, is the fifteen ratchet ARMS (~112s of a 127-137s re-round).
  GATE_T_STATICS_END="$(date +%s)"

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
      # Basenames are matched, so a path form is fine.
      #
      # CORRECTED 2026-08-11 (land-architecture-100p §5 P2). This comment used to read "Failure to
      # resolve the range yields an EMPTY own-set, which the lint treats as STRICT — the fail-closed
      # direction, never fail-open." Both halves are false, and the same claim had been copied into
      # four sibling arms. `in_own` reads a SET-BUT-EMPTY own-set as "nothing is mine ⇒ block on
      # nothing" (test-hermeticity-lint.sh:1288 `[ -n "$2" ] || return 1`), so a failed `git diff`
      # fails OPEN, not closed. The direction is a deliberate trade rather than a bug — a docs-only
      # land must not be judged by a corpus it did not touch, and that is the SAME state — but a
      # comment asserting the opposite is what stops the next author from noticing the exposure.
      # The strict state is reachable only by NOT setting the variable at all, which is what
      # own_run() above now does for the `=off` kill switch.
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
    own_run HERM CC_HERM_OWN "$own" "$HERM_LINT" tests >&2 || herm_rc=$?
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
      gate_red hermeticity
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
    own_run WALL CC_WALLTIME_OWN "$wown" "$WALL_LINT" tests >&2; _arm_rc=$?
    if (( _arm_rc == 2 )); then arm_nonverdict "test-walltime-lint"; return 1; fi
    if (( _arm_rc != 0 )); then
      echo "✗ gate: wall-clock RED — a fixture THIS LAND CHANGES seeds a future absolute date." >&2
      echo "  Seed relative to now instead; the file and dates are named above." >&2
      gate_red walltime
      return 1
    fi
  fi

  # ── AF_UNIX absolute-bind ratchet (2026-08-09) ────────────────────────────────────────────────
  # Same own-scope contract as the ratchets around it, for the blocker class with the WORST possible
  # polarity: a fixture that binds an AF_UNIX socket by absolute path is green in every hand-check
  # and red only inside postland-verify, whose TMPDIR is ~70 bytes longer — and postland's own
  # printed re-run command uses a short /tmp path, so the operator's repro EXONERATES the file.
  # Measured: tests/boot-resume-launch.bats sat in 17 of 17 postland reds across 40h, no green stamp
  # existed for that whole window, and deploy-live refused every sweep — so nothing that landed on
  # trunk reached the live ~/.claude layer. Two prior sessions each fixed the files in front of them
  # (item e1d43f93da19 fixed two on 2026-08-06) and neither could see the other two.
  #
  # It belongs HERE for the reason its siblings document: enforced only by its own suite it is
  # post-hoc DETECTION, and gate-select maps that suite from exactly one edge — the lint — so ADDING
  # a fixture never selects it (memory: enforcement-must-live-at-the-chokepoint). Sub-second, a pure
  # grep, and it names file and line to the session that wrote them.
  AFUNIX_LINT="${SHIP_LAND_AFUNIX_LINT:-scripts/test-afunix-path-lint.sh}"
  if [[ -d tests ]] && ls tests/*.bats >/dev/null 2>&1 && [[ -x "$AFUNIX_LINT" ]]; then
    local aown=""
    if [[ "${SHIP_LAND_AFUNIX_OWN_SCOPE:-on}" != "off" ]]; then
      aown="$(git diff --name-only "$range" -- 'tests/*.bats' 2>/dev/null || true)"
    fi
    echo "→ gate: AF_UNIX absolute-bind ratchet (104-byte sun_path bombs in fixtures)" >&2
    own_run AFUNIX CC_AFUNIX_OWN "$aown" "$AFUNIX_LINT" tests >&2; local arc=$?
    if [[ "$arc" -eq 2 ]]; then
      echo "⛔ gate: afunix-path-lint could not RUN (exit 2) — a NON-VERDICT, not a claim about your tree." >&2
      echo "  Nothing is wrong with your files. Re-run /ship when the box is quieter." >&2
      # GATE_KILLED, not gate_red: the line above says this is NOT a claim about the tree,
      # yet gate_red made it exit 6 (author-fixable RED) instead of 9 (retryable machine
      # verdict) — the distinction :90 calls load-bearing. The git-identity arm at :1792
      # had this shape right; these two did not.
      GATE_KILLED=1
      return 1
    elif [[ "$arc" -ne 0 ]]; then
      echo "✗ gate: AF_UNIX RED — a fixture THIS LAND CHANGES binds a socket by absolute path." >&2
      echo "  It will pass for you and red the whole tree inside postland; the fix is named above." >&2
      gate_red afunix
      return 1
    fi
  fi

  # ── moving-ref pre-fix-control ratchet (2026-08-13) ───────────────────────────────────────────
  # Same own-scope contract as the ratchets around it, for a class whose two outcomes are BOTH bad
  # and only one of them is visible: a control replayed from `git show origin/main:<path>` stops
  # being a pre-fix artifact the instant the fix lands on origin/main. It then either reddens
  # permanently (tests/capacity-alarm-permb.bats on 2026-08-11; tests/compressor-sentinel.bats cases
  # 72/75/76, RED ON TRUNK since 6dd3ea468 and repaired in this same diff) or — worse — passes
  # VACUOUSLY, because the post-fix artifact happens to answer the same way for an unrelated reason
  # (tests/ignition-gate-census.bats: 9/9 green while replaying the fixed gate). A red control gets
  # fixed; a vacuous one gets trusted.
  #
  # It belongs HERE for the reason its siblings document: enforced only by its own suite it is
  # post-hoc DETECTION, and gate-select maps that suite from exactly one edge — the lint — so
  # WRITING a new control never selects it (memory: enforcement-must-live-at-the-chokepoint). This
  # is the THIRD instance of one greppable mistake and the memory carrying the rule since
  # 2026-07-29 did not reach an author twelve days later; that is what makes it a gate, not a note.
  # Sub-second, a pure awk, and it names file, line and the offending ref.
  MOVINGREF_LINT="${SHIP_LAND_MOVINGREF_LINT:-scripts/moving-ref-control-lint.sh}"
  if [[ -d tests ]] && ls tests/*.bats >/dev/null 2>&1 && [[ -x "$MOVINGREF_LINT" ]]; then
    local mown=""
    if [[ "${SHIP_LAND_MOVINGREF_OWN_SCOPE:-on}" != "off" ]]; then
      mown="$(git diff --name-only "$range" -- 'tests/*.bats' 2>/dev/null || true)"
    fi
    echo "→ gate: moving-ref control ratchet (a pre-fix control replayed from a ref that advances)" >&2
    own_run MOVINGREF CC_MOVINGREF_OWN "$mown" "$MOVINGREF_LINT" tests >&2; local mrc=$?
    if [[ "$mrc" -eq 2 ]]; then
      echo "⛔ gate: moving-ref-control-lint could not RUN (exit 2) — a NON-VERDICT, not a claim about your tree." >&2
      echo "  Nothing is wrong with your files. Re-run /ship when the box is quieter." >&2
      GATE_KILLED=1
      return 1
    elif [[ "$mrc" -ne 0 ]]; then
      echo "✗ gate: MOVING-REF RED — a control THIS LAND CHANGES replays from a ref that will move past it." >&2
      echo "  It will pass for you and then compare the fix to itself; the fix is named above." >&2
      gate_red movingref
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
    own_run GITID CC_GITID_OWN "$gown" "$GITID_LINT" >&2 || gitid_rc=$?
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
      gate_red git-identity
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
      # REPO-RELATIVE, and the `| sed 's:^[^/]*/::'` that used to strip the leading component is
      # GONE (2026-08-15, backlog c1a29f8ee045). The lint scans bin/, hooks/ and scripts/ as three
      # separate roots, so the strip was how a repo-relative path was made to match what the lint
      # reported — and it MERGED the three namespaces on the way: `bin/cc-foo` and `scripts/cc-foo`
      # both became `cc-foo`, so a diff touching one blocked the land over the other. Latent only
      # because no basename collides across those dirs today, which is a property of the tree.
      # utc-stamp-lint's in_own now matches the FULL scanned path on a component boundary, so the
      # unstripped path is what it wants; the two changes are one fix and must land together.
      # lint_own_scope preserves that: it echoes `git diff --name-only` verbatim, unstripped.
      #
      # The pathspec is now ASKED FOR rather than restated (it used to hardcode `'bin/*' 'hooks/*'
      # 'scripts/*'`), so utc-stamp-lint's EMBEDDED_DIRS moves both at once — see lint_own_scope.
      uown="$(lint_own_scope "$UTC_LINT" "$range")" || {
        arm_nonverdict "utc-stamp-lint" \
          "It could not name the population it judges (--print-scope), so an own-set built here would be a GUESS at its scope."
        return 1; }
      [[ -n "$uown" ]] && echo "→ gate: utc-stamp own-scope — blocking on $(printf '%s\n' "$uown" | grep -c .) file(s) in this land's diff; others advisory." >&2
    fi
    echo "→ gate: UTC timestamp-contract ratchet (a Z suffix from a non-UTC clock)" >&2
    if ! "$UTC_LINT" --selftest >/dev/null 2>&1; then
      echo "✗ gate: utc-stamp-lint --selftest FAILED — the detector no longer discriminates, so its" >&2
      echo "  clean verdict would mean nothing. Fix the lint before landing." >&2
      gate_red utc-stamp-selftest
      return 1
    fi
    own_run UTC CC_UTC_OWN "$uown" "$UTC_LINT" >&2; _arm_rc=$?
    if (( _arm_rc == 2 )); then arm_nonverdict "utc-stamp-lint"; return 1; fi
    if (( _arm_rc != 0 )); then
      echo "✗ gate: UTC-stamp RED — a file THIS LAND CHANGES stamps a literal Z from a local clock." >&2
      echo "  Add -u to the date call (or emit %z instead of Z); the file and lines are named above." >&2
      gate_red utc-stamp
      return 1
    fi
  fi

  # ── pipefail/SIGPIPE ratchet (backlog 791345455b58) ───────────────────────────────────────────
  # Fifth deterministic blocker class, same own-scope contract as the ratchets above. `producer |
  # grep -q PAT` under `set -o pipefail` reads FALSE **on a match**: grep exits at the match, the
  # producer takes SIGPIPE on its next write, and pipefail promotes that 141 over grep's 0. It
  # presents as flake, not failure, and instrumentation HIDES it — anything that slows the pipe
  # closes the window, so "works when traced" is not evidence.
  #
  # Not hypothetical, and not rare: ec9a43a9 fixed it in cc-relogin-poll's capability probe, and the
  # 2026-08-08 sweep behind this ratchet found 22 more live sites — including a version gate that
  # had been failing 100% of the time over a 245 MB binary, a launchd liveness check reporting jobs
  # NOT loaded while loaded, and the worktree guard's cwd leg reading "nothing live" 60/60 on a true
  # match, which inverted a SAFETY refusal whose own header says it can only fail open.
  #
  # It belongs HERE and not only in its own bats suite, for the reason the ratchets above document:
  # a lint enforced solely by its own suite is post-hoc DETECTION, and gate-select will not pick that
  # suite up when the edited file is a PRODUCER rather than the lint. At the gate it is scope-
  # independent, sub-second, and names the file to the session that wrote it.
  #
  # --selftest runs alongside the scan: the fixtures replay the scar shapes verbatim (so the lint
  # cannot scan itself — see the self-exclusion in scan()), and the selftest is what proves the
  # detector still discriminates. A ratchet whose own discrimination is unverified is not a gate —
  # and this detector has a specific way of dying quiet: it is an awk program inside a single-quoted
  # bash string, where one stray apostrophe truncates it into something that matches nothing and
  # reports a clean tree. It exits 2 on that, and exit 2 is treated as a NON-VERDICT below.
  PF_LINT="${SHIP_LAND_PIPEFAIL_LINT:-scripts/pipefail-sigpipe-lint.sh}"
  if [[ -x "$PF_LINT" ]]; then
    local pown=""
    if [[ "${SHIP_LAND_PIPEFAIL_OWN_SCOPE:-on}" != "off" ]]; then
      # ASKED FOR, not restated — and this arm is the one that proves the rule empirically. The
      # hardcoded line here read `'bin/*' 'hooks/*' 'scripts/*' 'tests/*' 'docs/*' '*.sh'`, which
      # had ALREADY drifted from the lint in both directions: no `*.bats` (so a .bats file outside
      # tests/ was judged and could never block — silent advisory, the dangerous direction), plus
      # `tests/*` and `docs/*` that the lint only ever reaches through `*.sh`/`*.bats` anyway. No
      # env seam was needed for that; a code edit did it. See lint_own_scope.
      pown="$(lint_own_scope "$PF_LINT" "$range")" || {
        arm_nonverdict "pipefail-sigpipe-lint" \
          "It could not name the population it judges (--print-scope), so an own-set built here would be a GUESS at its scope."
        return 1; }
      [[ -n "$pown" ]] && echo "→ gate: pipefail-sigpipe own-scope — blocking on $(printf '%s\n' "$pown" | grep -c .) file(s) in this land's diff; others advisory." >&2
    fi
    echo "→ gate: pipefail/SIGPIPE ratchet (an early-exit pipe consumer that reads FALSE on a match)" >&2
    local pf_self=0
    "$PF_LINT" --selftest >/dev/null 2>&1 || pf_self=$?
    if (( pf_self != 0 )); then
      echo "✗ gate: pipefail-sigpipe-lint --selftest FAILED — the detector no longer discriminates," >&2
      echo "  so its clean verdict would mean nothing. Fix the lint before landing." >&2
      gate_red pipefail-sigpipe-selftest
      return 1
    fi
    local pf_rc=0
    own_run PIPEFAIL CC_PIPEFAIL_OWN "$pown" "$PF_LINT" >&2 || pf_rc=$?
    if (( pf_rc == 2 )); then
      echo "⛔ gate: pipefail-sigpipe-lint could not RUN (exit 2) — a NON-VERDICT, not a claim about" >&2
      echo "  your tree. Nothing is wrong with the files named above (if any)." >&2
      GATE_KILLED=1
      return 1
    fi
    if (( pf_rc != 0 )); then
      echo "✗ gate: pipefail-SIGPIPE RED — a file THIS LAND CHANGES pipes a streaming producer into" >&2
      echo "  an early-exit consumer under pipefail, so the condition reads FALSE on a MATCH." >&2
      echo "  Drain it: 'grep -q P' → 'grep P >/dev/null'; 'head -N' → \"awk 'NR<=N'\". Where draining" >&2
      echo "  is expensive, neutralise instead: '{ p || true; } | grep -q P' keeps the early exit." >&2
      echo "  If you FIXED a grandfathered site, lower its count in scripts/pipefail-sigpipe-allow.txt." >&2
      gate_red pipefail-sigpipe
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
      # THE DISCRIMINATOR IS rc PLUS stdout, and until 2026-08-14 (backlog 73583e2519d6) it was
      # stdout ALONE — `… 2>/dev/null || true`, whose comment claimed it "yields NO verdict, never a
      # fabricated one". It yielded the GREEN one. An empty stdout is this lint's clean verdict, and
      # a missing python3, an unreadable suite, an uncaught traceback and a SIGKILL all produce an
      # empty stdout too, so every could-not-run read as "no dead assertions" — while the arm
      # printed its own "→ gate: bats dead-assertion ratchet" line as if it had checked.
      #
      # That is the OPPOSITE polarity from all fifteen neighbouring arms, which route could-not-run
      # to GATE_KILLED (exit 9, retryable) — and it is the worse direction. Fail-closed costs one
      # re-run on a noisy box; fail-open lets through exactly the class this ratchet exists to stop,
      # and that class's whole signature is being invisible: the dead assertion lands, its suite
      # passes, and the corpus goes red ~3.2h later in postland-verify, for everyone at once. The
      # ratchet was moved to this chokepoint because detection-later was a treadmill; a green that
      # means "the check did not run" puts it back on the treadmill silently.
      #
      #   rc 0                → clean
      #   findings on stdout  → RED, whatever the rc — a real verdict outranks a non-verdict, as
      #                         everywhere else in this gate (see run_scoped_suite)
      #   rc 1, stdout EMPTY  → an uncaught exception: python exits 1 with nothing on stdout, so
      #                         this shape is indistinguishable from "findings" by the CODE alone.
      #                         It is why the stdout leg stays in the discriminator after the fix.
      #   rc 2 / 127 / 128+n  → could-not-run: nothing readable to judge, no python3, killed.
      #
      # stderr is deliberately NOT swallowed any more: it carries the traceback that names WHY the
      # lint could not run, and a non-verdict whose cause is hidden is a non-verdict nobody fixes.
      # On a clean or a red run the lint writes nothing there (--summary is not passed), so this
      # adds no noise to the gate log.
      local drc=0
      dfind="$(python3 "$DEAD_LINT" --format text "${dscan[@]}")" || drc=$?
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
        gate_red dead-assertion
        return 1
      fi
      if (( drc != 0 )); then
        arm_nonverdict "bats-assert-liveness" \
          "python3 exited $drc with NO finding on stdout — no python3 on this box, an unreadable tests/*.bats, or a traceback (printed above)." \
          "$drc"
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
      # ASKED FOR rather than restated (it used to hardcode `'bin/*' 'hooks/*' 'scripts/*'`, which
      # is self-path-lint's $LAYERS written down a second time), so adding a fourth deployed layer
      # moves both at once — see lint_own_scope.
      spown="$(lint_own_scope "$SELFPATH_LINT" "$range")" || {
        arm_nonverdict "self-path-lint" \
          "It could not name the population it judges (--print-scope), so an own-set built here would be a GUESS at its scope."
        return 1; }
      [[ -n "$spown" ]] && echo "→ gate: self-path own-scope — blocking on $(printf '%s\n' "$spown" | grep -c .) file(s) in this land's diff; others advisory." >&2
    fi
    echo "→ gate: script-dir resolution ratchet (a repo root derived from an unresolved \$0)" >&2
    if ! "$SELFPATH_LINT" --selftest >/dev/null 2>&1; then
      echo "✗ gate: self-path-lint --selftest FAILED — the detector no longer discriminates, so its" >&2
      echo "  clean verdict would mean nothing. Fix the lint before landing." >&2
      gate_red self-path-selftest
      return 1
    fi
    own_run SELFPATH CC_SELFPATH_OWN "$spown" "$SELFPATH_LINT" >&2; _arm_rc=$?
    if (( _arm_rc == 2 )); then arm_nonverdict "self-path-lint"; return 1; fi
    if (( _arm_rc != 0 )); then
      echo "✗ gate: self-path RED — a file THIS LAND CHANGES derives a path via '..' from an" >&2
      echo "  unresolved \$0/\$BASH_SOURCE. Resolve the symlinks first (_resolve_self above); the" >&2
      echo "  file and lines are named above." >&2
      gate_red self-path
      return 1
    fi
  fi

  # ── pane-spawn coverage ratchet (2026-08-07, item 1467ea1dad4f) ───────────────────────────────
  # ~/.claude/logs/pane-spawns.jsonl exists to make ONE inference sound: a pane with no row was
  # spawned outside this tree. That is what separates §S4.1's two surviving hypotheses (an unlogged
  # caller vs an undocumented detached child), and it is worth exactly as much as its COVERAGE — a
  # single uninstrumented spawner turns "outside the tree" into "outside the tree, or that one
  # site", which is the ambiguity the item was filed to close.
  #
  # OWN-SCOPE, same contract as the three ratchets above — and it took the permission-gate lint to
  # get here. This block first shipped with own-scope deliberately OMITTED, reasoned as "an
  # own-scope filter would let an UNRELATED land introduce the exact spawner that re-opens the
  # ambiguity." That reasoning is FALSE and the lint's refusal is what exposed it: introducing a
  # spawner INTO a file IS changing that file, so it is inside the diff by construction and
  # own-scope cannot miss it. What the unscoped form did add was a real freeze mode — any
  # uninstrumented spawner anywhere blocks EVERY land by EVERYONE, with no event and no author to
  # act on it, which is precisely the 545-refusal standing state inertness-generator §2.3 records.
  PSPAWN_LINT="${SHIP_LAND_PSPAWN_LINT:-scripts/pane-spawn-coverage-lint.sh}"
  if [[ -x "$PSPAWN_LINT" ]]; then
    local psown=""
    if [[ "${SHIP_LAND_PSPAWN_OWN_SCOPE:-on}" != "off" ]]; then
      # Repo-relative, which is how this lint reports paths (it scans from the repo ROOT).
      # ASKED FOR rather than restated (it used to hardcode `'bin/*' 'hooks/*' 'scripts/*'
      # 'commands/*'`), so pane-spawn-coverage-lint's PSC_DIRS moves both at once. That matters
      # more here than anywhere else on this list: this lint underwrites "no row ⇒ not from this
      # tree", and one spawner that lands advisory instead of blocking ends that inference.
      # See lint_own_scope.
      psown="$(lint_own_scope "$PSPAWN_LINT" "$range")" || {
        arm_nonverdict "pane-spawn-coverage-lint" \
          "It could not name the population it judges (--print-scope), so an own-set built here would be a GUESS at its scope."
        return 1; }
      [[ -n "$psown" ]] && echo "→ gate: pane-spawn own-scope — blocking on $(printf '%s\n' "$psown" | grep -c .) file(s) in this land's diff; others advisory." >&2
    fi
    echo "→ gate: pane-spawn coverage ratchet (a spawn site that leaves no row)" >&2
    # gate_bounded: THE AUTHOR'S OWN DIFF — own-scope above means this can only refuse over a file
    # THIS land changes, so the refusal cannot outlive the diff that caused it and there is always
    # a named party who can clear it in one line. That is the budget: it expires when the diff does.
    # Set SHIP_LAND_PSPAWN_OWN_SCOPE=off and it reverts to the unbounded form, which is why the
    # scope is the declaration rather than a comment about intent.
    if ! "$PSPAWN_LINT" --selftest >/dev/null 2>&1; then
      echo "✗ gate: pane-spawn-coverage-lint --selftest FAILED — the detector no longer" >&2
      echo "  discriminates, so its clean verdict would mean nothing. Fix the lint before landing." >&2
      gate_red pane-spawn-selftest
      return 1
    fi
    # gate_bounded: THE AUTHOR'S OWN DIFF — see the marker above; CC_PSC_OWN carries the same
    # per-land scope into the lint, so an advisory finding outside the diff prints and never blocks.
    own_run PSPAWN CC_PSC_OWN "$psown" "$PSPAWN_LINT" >&2; _arm_rc=$?
    if (( _arm_rc == 2 )); then arm_nonverdict "pane-spawn-coverage-lint"; return 1; fi
    if (( _arm_rc != 0 )); then
      echo "✗ gate: pane-spawn coverage RED — a file THIS LAND CHANGES creates a terminal surface" >&2
      echo "  and never calls cc_log_pane_spawn (scripts/lib/pane-spawn-log.sh). Add the row, or the" >&2
      echo "  log's 'no row ⇒ not from this tree' inference is false; the lines are named above." >&2
      gate_red pane-spawn
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
      # advisory — so it is now ASKED FOR rather than restated here.
      #
      # THIS ARM IS THE PROOF THAT A COMMENT IS NOT A MECHANISM. The hardcoded line used to carry
      # `'tests/*'` and a paragraph explaining that it had to be added by hand when the lint gained
      # a THIRD population, the bats corpus — added only AFTER a bare `md5` in cc-queue.bats C12
      # passed vacuously on every scheduled run, which is the drift completing before anyone saw
      # it. Deriving from unattended-path-lint's EMBEDDED_SCOPE makes a fourth population arrive
      # here for free. `'launchd/*'` is deliberately gone with the restatement: emit() names the
      # TARGET script a plist executes, never the plist, so no finding and no allowlist key can
      # carry a plist path and that entry could only ever be inert. See lint_own_scope.
      upown="$(lint_own_scope "$UNATTENDED_LINT" "$range")" || {
        arm_nonverdict "unattended-path-lint" \
          "It could not name the population it judges (--print-scope), so an own-set built here would be a GUESS at its scope."
        return 1; }
      [[ -n "$upown" ]] && echo "→ gate: unattended-path own-scope — blocking on $(printf '%s\n' "$upown" | grep -c .) file(s) in this land's diff; others advisory." >&2
    fi
    echo "→ gate: bare-name binaries on unattended paths (launchd jobs + hooks + the bats corpus)" >&2
    if ! "$UNATTENDED_LINT" --selftest >/dev/null 2>&1; then
      echo "✗ gate: unattended-path-lint --selftest FAILED — the detector no longer discriminates, so" >&2
      echo "  its clean verdict would mean nothing. Fix the lint before landing." >&2
      gate_red unattended-path-selftest
      return 1
    fi
    own_run UNATTENDED CC_UNATTENDED_OWN "$upown" "$UNATTENDED_LINT" >&2; _arm_rc=$?
    if (( _arm_rc == 2 )); then arm_nonverdict "unattended-path-lint"; return 1; fi
    if (( _arm_rc != 0 )); then
      echo "✗ gate: unattended-path RED — a file THIS LAND CHANGES invokes a binary by bare name that" >&2
      echo "  is unreachable on the PATH it will actually run with. Resolve it absolutely, or harden" >&2
      echo "  PATH at the top of the file; the file, line and binary are named above." >&2
      gate_red unattended-path
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
      # component strip. The pathspec must cover every population the lint judges — and it is now
      # ASKED FOR rather than restated here, so widening CC_PERMGATE_SET moves both at once. The
      # previous line hardcoded `'install.sh' 'scripts/*'` under a comment asking the next author to
      # keep it in step by hand; see lint_own_scope for why that could only fail silently.
      pgown="$(lint_own_scope "$PERMGATE_LINT" "$range")" || {
        arm_nonverdict "permission-gate-lint" \
          "It could not name the population it judges (--print-scope), so an own-set built here would be a GUESS at its scope."
        return 1; }
      [[ -n "$pgown" ]] && echo "→ gate: permission-gate own-scope — blocking on $(printf '%s\n' "$pgown" | grep -c .) file(s) in this land's diff; others advisory." >&2
    fi
    echo "→ gate: unbounded permission gates on the actuation paths (install · deploy · land)" >&2
    if ! "$PERMGATE_LINT" --selftest >/dev/null 2>&1; then
      echo "✗ gate: permission-gate-lint --selftest FAILED — the detector no longer discriminates, so" >&2
      echo "  its clean verdict would mean nothing. Fix the lint before landing." >&2
      gate_red permission-gate-selftest
      return 1
    fi
    own_run PERMGATE CC_PERMGATE_OWN "$pgown" "$PERMGATE_LINT" >&2; _arm_rc=$?
    if (( _arm_rc == 2 )); then arm_nonverdict "permission-gate-lint"; return 1; fi
    if (( _arm_rc != 0 )); then
      echo "✗ gate: permission-gate RED — a file THIS LAND CHANGES gained a guard-refusal on an" >&2
      echo "  actuation path with no declared bound (or its ratchet line is stale). Give the gate a" >&2
      echo "  budget whose expiry converts the standing state into an EVENT, then declare it with a" >&2
      echo "  \`gate_bounded: <what expires, and into what>\` marker; the lines are named above." >&2
      gate_red permission-gate
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
      # ASKED FOR rather than restated (it used to hardcode `'bin/*' 'hooks/*' 'scripts/*'
      # 'tools/*'`), so chromium-bundle-lint's EMBEDDED_DIRS moves both at once — see
      # lint_own_scope. This arm is the quietest of the eight: its class is invisible to every
      # other check (nothing slow, nothing red, no test fails), so a finding silently degraded to
      # advisory would land and show up only as a strobing Dock on the operator's own screen.
      cbown="$(lint_own_scope "$CHROMIUM_LINT" "$range")" || {
        arm_nonverdict "chromium-bundle-lint" \
          "It could not name the population it judges (--print-scope), so an own-set built here would be a GUESS at its scope."
        return 1; }
    fi
    echo "→ gate: chromium-bundle ratchet (a headless screenshot path launching the full app bundle)" >&2
    if ! "$CHROMIUM_LINT" --selftest >/dev/null 2>&1; then
      echo "✗ gate: chromium-bundle-lint --selftest FAILED — the detector no longer discriminates," >&2
      echo "  so its clean verdict would mean nothing. Fix the lint before landing." >&2
      gate_red chromium-bundle-selftest
      return 1
    fi
    own_run CHROMIUM CC_CHROMIUM_OWN "$cbown" "$CHROMIUM_LINT" >&2; _arm_rc=$?
    if (( _arm_rc == 2 )); then arm_nonverdict "chromium-bundle-lint"; return 1; fi
    if (( _arm_rc != 0 )); then
      echo "✗ gate: chromium-bundle RED — a file THIS LAND CHANGES takes screenshots through the" >&2
      echo "  full Chromium.app bundle, which strobes the operator's Dock once per launch. Use" >&2
      echo "  resolve_headless_chrome from scripts/lib/cc-common.sh; the file is named above." >&2
      gate_red chromium-bundle
      return 1
    fi
  fi

  # ── TSV field-collapse ratchet (backlog e146d30857b4) ─────────────────────────────────────────
  # Same own-scope contract as the ratchets around it. Tab is IFS-WHITESPACE, so `IFS=<tab> read`
  # collapses a run of delimiters: an empty cell does not read back empty, it shifts every later
  # column LEFT, silently, exit 0. Producers must guarantee non-empty cells at the EMITTER.
  #
  # It belongs HERE, and this class is the cleanest proof of the rule its siblings state. The
  # convention HAS had a repo-wide assertion since 2026-07-25 — tests/tsv-field-collapse.bats §3 —
  # and that suite blocked NONE of the lands that broke it: it re-reddened three times with a
  # completely different offender set each time and zero overlap between them (six discharged by
  # 68e17e2a on 2026-07-31; six more landed by 2026-08-07, five of them AFTER that discharge; two
  # more by 2026-08-10). gate-select's `cited_only` (:280) is why — a DIRECT edge needs the path in
  # the suite's EXECUTABLE text, and the guard named files only inside its exemption heredoc, so a
  # BRAND-NEW script is named nowhere, its failure is exonerable-as-adjacent, and the land passes.
  # Measured on a planted offender before this block existed: `gate-select --direct` on the land
  # that ADDS an unpadded reader returns ZERO hits for tsv-field-collapse.bats. A suite that can
  # only fail after the offender has landed is post-hoc DETECTION
  # (memory: enforcement-must-live-at-the-chokepoint); the gate is the only place that reaches the
  # author who is adding the reader. Sub-second, a pure grep, and it names file and line.
  #
  # NO --selftest LEG HERE, unlike chromium-bundle/permission-gate, and the omission is the
  # considered choice rather than a gap. Their shape — "selftest fails ⇒ gate_red ⇒ every land
  # blocked until someone fixes the detector" — is a STANDING state on the actuation path, which is
  # exactly what permission-gate-lint's own doctrine forbids without a declared budget. This land
  # met that gate live: `permission-gate-lint --selftest` went stale and refused the land on its own
  # detector's health, not on this tree. Adding a fourth instance and declaring a bound I could not
  # honestly name would be laundering. The claim it protects is already enforced where it belongs:
  # tests/tsv-field-collapse.bats runs `--selftest` and requires exit 0, and that suite names
  # scripts/tsv-pad-lint.sh in its EXECUTABLE text — so it is a DIRECT suite of any land that
  # touches the lint, which is the only land that can break its discrimination. Same reasoning as
  # own-scope one paragraph up: never convert one broken thing into a refusal of every author.
  TSVPAD_LINT="${SHIP_LAND_TSVPAD_LINT:-scripts/tsv-pad-lint.sh}"
  if [[ -x "$TSVPAD_LINT" ]]; then
    local tsvown=""
    if [[ "${SHIP_LAND_TSVPAD_OWN_SCOPE:-on}" != "off" ]]; then
      # The pathspec must list every population the lint judges, or a land adding an unpadded reader
      # to a dir the pathspec misses yields an own-set without it, the lint reports it advisory, and
      # the rule is detection again. It is now ASKED FOR rather than restated (the line used to
      # hardcode `'bin/*' 'hooks/*' 'scripts/*'`), so CC_TSVPAD_DIRS moves both at once —
      # see lint_own_scope. A docs-only land still yields an EMPTY own-set and blocks on nothing.
      tsvown="$(lint_own_scope "$TSVPAD_LINT" "$range")" || {
        arm_nonverdict "tsv-pad-lint" \
          "It could not name the population it judges (--print-scope), so an own-set built here would be a GUESS at its scope."
        return 1; }
    fi
    echo "→ gate: TSV field-collapse ratchet (an IFS=tab reader whose producer can emit an empty cell)" >&2
    own_run TSVPAD CC_TSVPAD_OWN "$tsvown" "$TSVPAD_LINT" . >&2; local trc=$?
    if [[ "$trc" -eq 2 ]]; then
      echo "⛔ gate: tsv-pad-lint could not RUN (exit 2) — a NON-VERDICT, not a claim about your tree." >&2
      echo "  Nothing is wrong with your files. Re-run /ship when the box is quieter." >&2
      # GATE_KILLED, not gate_red — see the afunix arm above; same defect, same reason.
      GATE_KILLED=1
      return 1
    elif [[ "$trc" -ne 0 ]]; then
      echo "✗ gate: TSV field-collapse RED — a file THIS LAND CHANGES reads IFS=tab TSV with nothing" >&2
      echo "  guaranteeing a non-empty cell. Pad at the EMITTER (the read side cannot be repaired);" >&2
      echo "  the file, the line and the \`def cell(ph)\` to paste are named above." >&2
      gate_red tsv-pad
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
  #
  # NO `command -v shellcheck` IN THE APPLICABILITY CONDITION (2026-08-11, grok-wiki tests shard
  # candidate 1, backlog 9ea31151dd94). It used to read `… && command -v shellcheck`, which made a
  # missing tool a SILENT SKIP: on a host without shellcheck this whole ratchet vanished and the
  # land said nothing, while the sibling .sh path — bare `shellcheck "${sc_todo[@]}"` above — fails
  # loudly at 127 for any diff touching a *.sh. So a .bats-only land got ZERO shellcheck coverage
  # and read exactly like a clean one. The lint itself has ALWAYS handled this correctly: it exits
  # 2 with "⛔ shellcheck not installed — NOT a clean verdict". The guard is what stopped anyone
  # from ever seeing that. Removing it routes the absence through the exit-2 arm below, which is
  # the same NON-VERDICT ⇒ GATE_KILLED shape the hermeticity, afunix, git-identity, pipefail and
  # tsv-pad arms already use. Exit 2 must NOT become gate_red: a could-not-run dressed up as a RED
  # is a false claim about the lander's tree (backlog 9c5d0ba74e79).
  SC_BATS_LINT="${SHIP_LAND_BATS_SC_LINT:-scripts/bats-shellcheck-lint.sh}"
  if [[ -d tests ]] && ls tests/*.bats >/dev/null 2>&1 && [[ -x "$SC_BATS_LINT" ]]; then
    local bown=""
    if [[ "${SHIP_LAND_BATS_SC_OWN_SCOPE:-on}" != "off" ]]; then
      # Failure to resolve the range yields an EMPTY own-set, which means "I wrote no line" ⇒
      # nothing blocks.
      #
      # CORRECTED 2026-08-11 (land-architecture-100p §5 P2): this used to add "and the opposite of
      # the siblings': their strict fallback is free because their corpus is clean". That is wrong
      # about the siblings. Measured across all thirteen lints, TWELVE degrade permissive on a
      # set-but-empty own-set exactly as this one does (`${VAR+set}` + `[ -n "$2" ] || return 1`);
      # only chromium-bundle degraded strict, and that was the leak fixed in this same diff. So
      # this arm's degradation is the HOUSE RULE, not an exception to it. What IS distinctive here
      # is the magnitude of the alternative: a strict whole-tree run of this lint is 164 findings,
      # i.e. a guaranteed outage on every land, where a sibling's strict run is clean.
      bown="$("$SC_BATS_LINT" --own-lines "$range" 2>/dev/null || true)"
      [[ -n "$bown" ]] && echo "→ gate: bats-shellcheck own-scope — blocking on $(printf '%s\n' "$bown" | grep -c .) changed line(s); pre-existing findings advisory." >&2
    fi
    echo "→ gate: .bats shellcheck ratchet (this gate never linted a test file before)" >&2
    # `--own-lines` above is deliberately NOT part of this: it parses a diff and needs no linter
    # at all, so it keeps working on a host without the tool and an unresolvable range keeps
    # meaning "I wrote no line", exactly as before.
    local scrc=0
    "$SC_BATS_LINT" --selftest >/dev/null 2>&1 || scrc=$?
    if [[ $scrc -eq 2 ]]; then bats_sc_nonverdict; return 1; fi
    if [[ $scrc -ne 0 ]]; then
      echo "✗ gate: bats-shellcheck-lint --selftest FAILED — the lint no longer discriminates, so its" >&2
      echo "  clean verdict would mean nothing. Fix the lint before landing." >&2
      gate_red bats-shellcheck-selftest
      return 1
    fi
    scrc=0
    own_run BATS_SC CC_BATS_SC_OWN "$bown" "$SC_BATS_LINT" tests >&2 || scrc=$?
    if [[ $scrc -eq 2 ]]; then bats_sc_nonverdict; return 1; fi
    if [[ $scrc -ne 0 ]]; then
      echo "✗ gate: bats-shellcheck RED — a line THIS LAND WROTE carries a shellcheck finding," >&2
      echo "  or a suite it touches aborts shellcheck entirely. Both are named above." >&2
      gate_red bats-shellcheck
      return 1
    fi
  fi

  # ── unguarded-kill ratchet: the load-flake class that has been fixed BY HAND eight times ─────────
  # `kill "$p" 2>/dev/null` with no `|| true`. Once the child is REAPED the kill returns 1 (ESRCH),
  # bats' errexit aborts the body, and a test that passed on its own merits goes red — only under
  # load, never in isolation. It has cost this gate a refused push already (debc016f: the bats
  # retry's extra executed count tripped the 1614≠1613 plan mismatch). Four commits fixed nine sites
  # by hand; nothing ever stopped the tenth, and eleven had re-accumulated by 2026-08-09.
  #
  # NO GRANDFATHER LIST, unlike its four own-scoped neighbours above: they carry inherited debt, this
  # one does not, because the commit that introduced it swept the corpus to zero first. It was also
  # STRICT WHOLE-CORPUS on that basis — and that half is now gone (backlog e191b6801be5). "The
  # baseline is zero" is a RUNTIME invariant nothing re-asserts, so the argument held only until the
  # first sibling landed an unguarded kill; from that moment the arm refuses EVERY land in the fleet
  # over a file the author never opened, naming a remedy that is not theirs. It now takes the same
  # three-state own-set as its neighbours — absent ⇒ strict (postland, a bare human run), set-but-
  # empty ⇒ nothing blocks, set ⇒ those files block and the rest are REPORTED advisory — so the
  # class stays visible without taxing an innocent lander. Still no exemption list to rot, and still
  # ~0.2s over 355 suites.
  KILL_GUARD_LINT="${SHIP_LAND_KILL_GUARD_LINT:-scripts/bats-kill-guard-lint.sh}"
  # gate_bounded: EVENT-ON-FIRST-LAND, DIFF-SCOPED, ONE-TOKEN-CLEARABLE — neither refusal below can
  # become a standing state nobody is told about (the 545-refusal scar, inertness-generator §2.3).
  # The scan refusal names the exact file:line:col and prints the whole remedy, so it is an EVENT
  # with an actor: the author who typed the kill clears it with `|| true` in the same edit, and it
  # cannot fire for anyone else because the corpus baseline is zero. The selftest refusal fires on
  # the FIRST land after the lint stops discriminating rather than after a clock, which §9 of
  # permission-gate-lint calls strictly stronger than a budget — and it is the only thing standing
  # between a broken detector and a clean verdict that means nothing. Declared release if either
  # ever does wedge a land it should not: `SHIP_LAND_KILL_GUARD_LINT=/nonexistent` skips this block
  # whole (the -x test below), which is auditable in land.log rather than silent.
  if [[ -d tests ]] && ls tests/*.bats >/dev/null 2>&1 && [[ -x "$KILL_GUARD_LINT" ]]; then
    echo "→ gate: unguarded-kill ratchet (a kill whose stderr is silenced and whose status is not)" >&2
    # --selftest alongside the scan, for the reason the UTC ratchet documents: a ratchet whose own
    # discrimination is unverified is not a gate. Its controls replay the real flaking lines from
    # f676d2f6/e90476e6 byte-for-byte, and both exemptions are proven narrow in both directions.
    if ! "$KILL_GUARD_LINT" --selftest >/dev/null 2>&1; then
      echo "✗ gate: bats-kill-guard-lint --selftest FAILED — the lint no longer discriminates, so its" >&2
      echo "  clean verdict would mean nothing. Fix the lint before landing." >&2
      gate_red kill-guard-selftest
      return 1
    fi
    local kgown=""
    if [[ "${SHIP_LAND_KILL_GUARD_OWN_SCOPE:-on}" != "off" ]]; then
      # The pathspec is the arm's whole population: this lint judges .bats suites and nothing else,
      # so widening it would hand over names the lint can never match and narrowing it would let a
      # land ADD an unguarded kill that the arm then reports advisory — detection, not a gate
      # (memory: enforcement-must-live-at-the-chokepoint). A docs-only land yields an EMPTY own-set
      # and blocks on nothing, which is the point.
      kgown="$(git diff --name-only "$range" -- 'tests/*.bats' 2>/dev/null || true)"
      [[ -n "$kgown" ]] && echo "→ gate: kill-guard own-scope — blocking on $(printf '%s\n' "$kgown" | grep -c .) file(s) in this land's diff; others advisory." >&2
    fi
    own_run KILL_GUARD CC_KILLGUARD_OWN "$kgown" "$KILL_GUARD_LINT" tests >&2; _arm_rc=$?
    if (( _arm_rc == 2 )); then arm_nonverdict "bats-kill-guard-lint"; return 1; fi
    if (( _arm_rc != 0 )); then
      echo "✗ gate: unguarded-kill RED — a kill in a suite THIS LAND CHANGES silences its stderr but" >&2
      echo "  not its exit status, so a reaped child aborts the test body under load. Guard it: '|| true'." >&2
      gate_red kill-guard
      return 1
    fi
  fi

  # ── @test-name EVAL ratchet (a name that EXPANDS loses the expanded word, silently) ─────────────
  # Sits beside kill-guard because it shares its shape exactly: whole-corpus, STRICT, no allowlist,
  # because the baseline was swept to zero first (8942 @test lines, 0 offenders). bats evals every
  # description, so a backtick / $( ) / $VAR in a NAME is substituted and the word is DELETED from
  # the rendered TAP name — and the SILENT variant (an unset var, or a word that IS a command like
  # bats' own `run`) passes with no diagnostic at all. Two live sites were measured and fixed on
  # 2026-08-13 (announce-before-retire.bats:356, handoff-recycle-engagement.bats:101), 3 days after
  # the class was swept — which is exactly why detection in a suite is not enforcement.
  TESTNAME_LINT="${SHIP_LAND_TESTNAME_LINT:-scripts/bats-testname-eval-lint.sh}"
  # gate_bounded: EVENT-ON-FIRST-LAND, DIFF-SCOPED, ONE-BACKSLASH-CLEARABLE — neither refusal can
  # become a standing state. The scan names file:line and prints the whole cure (escape it), so it is
  # an EVENT with an actor: the author who typed the name clears it in the same edit, and it cannot
  # fire for anyone else because the corpus baseline is zero. Release valve, auditable in land.log:
  # SHIP_LAND_TESTNAME_LINT=/nonexistent skips this block whole via the -x test.
  if [[ -d tests ]] && ls tests/*.bats >/dev/null 2>&1 && [[ -x "$TESTNAME_LINT" ]]; then
    echo "→ gate: @test-name eval ratchet (a name whose word is deleted by shell expansion)" >&2
    if ! "$TESTNAME_LINT" --selftest >/dev/null 2>&1; then
      echo "✗ gate: bats-testname-eval-lint --selftest FAILED — the lint no longer discriminates, so" >&2
      echo "  its clean verdict would mean nothing. Fix the lint before landing." >&2
      gate_red testname-eval-selftest
      return 1
    fi
    "$TESTNAME_LINT" tests >&2; _arm_rc=$?
    if (( _arm_rc == 2 )); then arm_nonverdict "bats-testname-eval-lint"; return 1; fi
    if (( _arm_rc != 0 )); then
      echo "✗ gate: @test-name eval RED — a name above EXPANDS, so bats deletes that word from the" >&2
      echo "  rendered TAP name and the suite still passes. Backslash-escape it: \\\` or \\\$." >&2
      gate_red testname-eval
      return 1
    fi
  fi

  # ── off-box ADMISSION ratchet — the LAST arm, because it is the only expensive one ────────────
  # THE GENERATOR IT CLOSES. `scripts/offbox-partition.sh` makes the hermetic partition a SET
  # DIFFERENCE, so a suite joins it BY EXISTING rather than by being proven off-box-clean. One
  # not-green suite makes hermetic.yml's binary conclusion non-green, so no off-box stamp is written
  # and `deploy-live.sh`'s T1H tier — the only tier that advances on a POSITIVE result with no lag
  # budget — is shut for the WHOLE MACHINE. The workflow never gates a land (by construction), so
  # that cost was paid by everyone and owed by nobody. Measured 2026-08-12: three folds in one day,
  # corpus 405 → 414, reds 2 → 3, with two suites fixed and staying fixed. Whack-a-mole cannot win
  # against a corpus that grows; moving the bill to the author can.
  #
  # WHY IT IS SAFE TO PUT A BATS RUN IN THE ARMS. It costs ONE `git diff` on the overwhelmingly
  # common land, because it binds only on suites this range ADDS — usually none. When it does fire it
  # runs exactly the added suite under the producer's own bound (300s), and that is the author's own
  # file. It sits LAST so every cheap deterministic arm has already had its say: a land that is going
  # to be refused for a 1s hermeticity finding should never first spend 300s here.
  #
  # WHY exit 2 IS A NON-VERDICT HERE TOO. The lint abstains when the runner cannot speak (no bats, no
  # timeout, a missing suite) rather than convicting on it — R6, the same rule its five sibling arms
  # route through GATE_KILLED. A gate that turned "this box has no timeout(1)" into "your suite is
  # broken" would teach authors to distrust every verdict it issues.
  # Resolved repo-root-relative and overridable by the same convention as HERM_LINT above: the tree
  # being landed must be gated by its OWN admission lint, so a land that legitimately changes the
  # gate is judged by the version it ships.
  local ADM_LINT="${SHIP_LAND_ADM_LINT:-scripts/offbox-admission-lint.sh}"
  if [[ -x "$ADM_LINT" ]] && [[ -d tests ]]; then
    local adm_rc=0
    "$ADM_LINT" --range "$range" >&2 || adm_rc=$?
    if (( adm_rc == 2 )); then
      echo "⛔ gate: offbox-admission could not RUN (exit 2) — a NON-VERDICT, not a claim about your tree." >&2
      echo "  Nothing is wrong with the suites named above (if any). Re-run /ship when the box is quieter." >&2
      GATE_KILLED=1
      return 1
    fi
    if (( adm_rc != 0 )); then
      echo "✗ gate: offbox-admission RED — a bats suite THIS LAND ADDS is not green off-box." >&2
      echo "  Landing it would red the hourly hermetic producer, write no off-box stamp, and shut" >&2
      echo "  deploy-live.sh's T1H tier for every session on this box until someone notices." >&2
      echo "  The cure is printed above and is ONE line, in this same commit: fix the suite, or list" >&2
      echo "  it in scripts/offbox-excluded.manifest with the measurement the lint just took." >&2
      # A REAL verdict: the lint names a suite and re-ran it deterministically, so exit 6 (fix your
      # tree), never a retryable 9 — same reasoning as the hermeticity and walltime ratchets.
      gate_red offbox-admission
      return 1
    fi
  fi

  # ── the test phase — SMOKE in the fast lane, the whole corpus only under the v1 kill switch ──
  # NOT gated on the statics rc above: an already-red land still runs the smoke, so the author gets
  # the lint error AND the failing test in ONE cycle. Same reasoning as run_corpus's no-fail-fast —
  # ≤120s on an already-doomed run buys every finding named at once instead of one per round-trip.
  local rbase direct
  GATE_T_ARMS_END="$(date +%s)"   # P0 phase boundary: the arms are done, the test phase begins
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
        SMOKE_STATE="none-locked"
        echo "→ gate[v1/locked]: statics + ratchets only — no bats inside the land-lock, in either lane." >&2
      elif [[ "$GATE_PRECHECK" = "1" ]]; then
        # The precheck's scope is lane-independent for the same reason: it is a claim about WHICH
        # PHASE runs, and the v1 kill switch changes only which phase the SMOKE step expands into.
        SMOKE_STATE="none-precheck"
        echo "→ gate[v1/precheck]: statics + ratchets only — the corpus is the land's, not the precheck's." >&2
      else
        direct="$("$GATE_SELECT" --direct "$range" ${EXTRA_RANGE:+"$EXTRA_RANGE"} 2>/dev/null || true)"
        [[ "$direct" = "FULL" ]] && direct=""   # "cannot decide" ⇒ exonerate nothing is unknown
        # The v1 kill switch runs the CORPUS, so there is no smoke to have a verdict about. Named
        # rather than left at the generic none: a v1 row and a lint-only v2 row are different lands.
        SMOKE_STATE="none-corpus"
        gate_home_setup
        run_corpus "$direct" || rc=1
      fi
    else
      run_smoke "$range" || rc=1
      SELECTED_N="$SMOKE_N"
    fi
  else
    # No tests/*.bats in this repo at all — a real and reachable cause, and the one that makes the
    # token set complete: every other `none-*` is a decision, this one is an absence.
    SMOKE_STATE="none-nosuites"
  fi
  gate_meas_close
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

# ── REBASE, HONOURING A rerere RESOLUTION GIT HAS ALREADY APPLIED ────────────────────────────
# `git rebase` returns non-zero the moment a conflict STOPS it — including when rerere.autoupdate
# (on globally: CLAUDE.md § Concurrent Sessions makes `git rerere` a standing setting) has already
# replayed a recorded resolution and STAGED every path. The tree at that point is fully resolved
# and one `--continue` from done, but a bare `if ! git rebase` reads only the exit CODE, calls it
# "resolve it by hand", and throws the resolution away.
#
# Measured 2026-08-17 on refs/land/failed: 789 pins. The top branch alone had been retried 112
# times across 5 days, and NO attempt was ever diagnosed — only counted. Replayed by hand,
# claude/fire-20260816T094145Z-41172-1 stopped with BOTH its conflicts already staged by rerere
# ("Staged '<path>' using previous resolution"), zero unmerged paths and zero conflict markers,
# and rebased clean in ONE `--continue`. So the retries were not failing because the conflict was
# hard; they were failing because the lander discarded a resolution git had already applied — and
# a retry can never fix that, which is exactly why the count grew instead of the queue draining.
#
# The question after a failed rebase is therefore not "did it exit non-zero" but "is anything
# ACTUALLY still unresolved". Both halves are checked, because each fails in a different direction:
#   * unmerged paths (diff-filter=U) — the TOO-WEAK half: rerere replays only what it has seen
#     before, so a partially-replayed rebase has real work left and MUST keep the exit-5 refusal.
#   * conflict markers in the staged content — the TOO-STRONG half: the precondition for
#     continuing is only "nothing is unmerged", i.e. SOMETHING staged every path. rerere is the
#     expected stager but is not provably the only one (a stray `git add` from an earlier aborted
#     attempt, a custom merge driver), and continuing over a marker lands `<<<<<<<` on trunk.
#     Measured 2026-08-17 — rerere ITSELF cannot reach this arm: staging a resolution that still
#     contains markers records ZERO postimages, so git never replays one. The arm is therefore
#     fail-closed cover for a non-rerere stager, and its worst case is the pre-existing exit 5;
#     tests/land-rerere-continue.bats pins it against a hand-staged marker, which is the reachable
#     population (memory: cap-whose-population-is-empty — do not pin a case that cannot happen).
# Only when both are clean do we continue. Anything else keeps the original refusal verbatim, with
# the rebase still in progress and the backup ref intact — the author's recovery path is unchanged.
rebase_onto_trunk() {  # $1=trunk → 0 = rebased (possibly via a rerere replay), 1 = real conflict
  local TRUNK="$1" tries=0 fp_before fp_after gd ga
  git rebase "origin/$TRUNK" >&2 && return 0

  while [ "$tries" -lt 50 ]; do
    tries=$((tries + 1))
    # genuinely unresolved paths ⇒ nothing to continue, keep the refusal
    [[ -n "$(git diff --name-only --diff-filter=U 2>/dev/null)" ]] && return 1
    # a rebase that stopped for a reason OTHER than a conflict stop (no rebase in progress at all —
    # e.g. the ref itself was bad) must not be "continued" either
    gd="$(git rev-parse --git-path rebase-merge 2>/dev/null || true)"
    ga="$(git rev-parse --git-path rebase-apply 2>/dev/null || true)"
    [[ -d "$gd" || -d "$ga" ]] || return 1
    if git diff --cached -U0 2>/dev/null | grep -qE '^\+(<{7}|={7}|>{7})([ 	]|$)'; then
      echo "✗ ship-land: a replayed rerere resolution staged conflict markers — refusing to continue the rebase." >&2
      return 1
    fi
    echo "→ ship-land: rebase conflict already resolved by git rerere (every path staged, no markers) — continuing (step ${tries})." >&2
    fp_before="$(git rev-parse HEAD 2>/dev/null || true)$(cat "$gd/msgnum" 2>/dev/null || true)"
    GIT_EDITOR=true git rebase --continue >&2 && return 0
    fp_after="$(git rev-parse HEAD 2>/dev/null || true)$(cat "$gd/msgnum" 2>/dev/null || true)"
    # no progress ⇒ `--continue` cannot resolve this one (e.g. the commit emptied out); refuse
    # rather than spin the bound down against an unchanging tree.
    [[ "$fp_before" = "$fp_after" ]] && return 1
  done
  return 1
}

unlocked_reconcile_and_gate() {  # $1=trunk $2=dry_run → sets GATE_BASE/GATE_HEAD globals;
                                 # exits internally on rebase-conflict(5) / gate-red(6) /
                                 # nothing-to-land(0) / --dry-run(0).
  local TRUNK="$1" DRY_RUN="$2"
  echo "→ ship-land[unlocked]: fetch + rebase + gate (statics + ratchets + bounded smoke) — no lock held" >&2
  git fetch origin "$TRUNK" 2>/dev/null || echo "⚠ ship-land: fetch failed — using local origin/$TRUNK" >&2

  if ! rebase_onto_trunk "$TRUNK"; then
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
  # BOUNDED (see git_net). A fetch that ERRORS keeps the old warn-and-proceed — the CAS below then
  # compares against a possibly-stale trunk and the push is still fail-closed (non-ff ⇒ exit 7). A
  # fetch that HANGS is a different animal: it holds the machine-wide mutex forever, so it aborts.
  git_net fetch origin "$TRUNK" 2>/dev/null \
    || { [[ "$NET_TIMED_OUT" = "1" ]] && net_timeout_abort "fetch origin $TRUNK" "${GATE_BASE:-?}" "Nothing was pushed."
         echo "⚠ ship-land: fetch failed — using local origin/$TRUNK" >&2; }

  local LAND_BASE
  if [[ -n "$GATE_BASE" ]]; then
    local now_base now_head
    now_base="$(git rev-parse "origin/$TRUNK" 2>/dev/null || echo '?')"
    now_head="$(git rev-parse HEAD 2>/dev/null || echo '?')"
    if [[ "$now_base" != "$GATE_BASE" || "$now_head" != "$GATE_HEAD" ]]; then
      echo "↻ ship-land[locked]: STALE GATE — origin/$TRUNK or HEAD moved during the unlocked gate (base ${GATE_BASE:0:7}→${now_base:0:7}, head ${GATE_HEAD:0:7}→${now_head:0:7}). Releasing the lock; re-reconciling + re-gating the new final tree unlocked." >&2
      # P0: this exit's row is written by the OUTER process, AFTER the lock is released — see the
      # `rc == 42` arm of the optimistic loop. Deliberately not here: this is the one exit that
      # fires while the mutex is held AND is not terminal, it is the hot path (74 stale rounds in
      # one day on the live box), and P1 spent a session emptying this lock. An instrument that
      # bought its own visibility with two git forks and a write inside the mutex would be paying
      # in the exact currency it exists to measure. The outer has every fact the row needs.
      exit 42
    fi
    LAND_BASE="$GATE_BASE"
  else
    if ! rebase_onto_trunk "$TRUNK"; then
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
  # The push's combined output is captured to a FILE and replayed, never swallowed: on a refusal the
  # refusing party is usually the pre-push hook, and its diagnostic is the only thing that says WHY.
  # A FILE and not `$(…)` deliberately — git_net sets NET_TIMED_OUT in the CURRENT shell, and a
  # command substitution would run it in a subshell and silently lose that flag, downgrading a
  # timeout (exit 10, a machine verdict, retryable) into an ordinary refusal.
  local PUSH_LOG; PUSH_LOG="$(mktemp)"
  if ! git_net push origin "HEAD:$TRUNK" >"$PUSH_LOG" 2>&1; then
    cat "$PUSH_LOG" >&2
    # A TIMED-OUT push is the one case where the outcome is genuinely UNKNOWN — the remote may have
    # taken it. Which is fine and needs no reconciliation here: nothing is deleted, the tree is
    # clean, and a re-run's preflight fetch decides it (already landed ⇒ "nothing to land"; not
    # landed ⇒ pushed again). Reading it as a non-ff rejection instead would be a claim about a
    # sibling that we have no evidence for.
    [[ "$NET_TIMED_OUT" = "1" ]] && net_timeout_abort "push origin HEAD:$TRUNK" "$LAND_BASE" \
      "Whether the remote took the push is UNKNOWN; the next /ship re-fetches and decides — it will land it, or find it already there."
    # ONE refusal statement, with the CAUSE selected into it. Two `echo … >&2` branches would read to
    # permission-gate-lint as two separate undeclared gates on an actuation path — and this is one
    # refusal that now knows why it fired, not a new gate. The exit code and the promises are
    # identical on both branches; only the sentence differs.
    local PUSH_WHY
    if [ "$(push_failure_kind "$(cat "$PUSH_LOG")")" = "non-ff" ]; then
      PUSH_WHY="REJECTED (non-fast-forward — a sibling beat you inside the window). Re-run /ship to re-fetch+rebase+re-verify."
    else
      PUSH_WHY="was turned away, and git rejected NO ref for a fast-forward reason — so this is NOT a trunk race and re-running /ship unchanged will not clear it. The party that turned it away is almost always the pre-push hook (githooks/pre-push — e.g. an unattributable author over the range); its output is above, verbatim. Fix what it names, then re-run /ship."
    fi
    rm -f "$PUSH_LOG"
    echo "✗ ship-land: push to origin/$TRUNK $PUSH_WHY Nothing was pushed; tree clean, backup ref ship/backup-* intact." >&2
    exit 7
  fi
  cat "$PUSH_LOG" >&2
  rm -f "$PUSH_LOG"

  while :; do
    # BOUNDED, and here a timeout must ABORT rather than fall through: land-verify would then read a
    # stale origin/$TRUNK, fail, and drive a spurious rebase+re-push loop — manufacturing a
    # content-drop verdict out of a network hang, inside the lock.
    git_net fetch origin "$TRUNK" 2>/dev/null \
      || { [[ "$NET_TIMED_OUT" = "1" ]] && net_timeout_abort "fetch origin $TRUNK" "$LAND_BASE" \
             "The push already succeeded; the next /ship will find it landed or re-verify it."; }
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
    local REPUSH_LOG; REPUSH_LOG="$(mktemp)"
    if ! git_net push origin "HEAD:$TRUNK" >"$REPUSH_LOG" 2>&1; then
      cat "$REPUSH_LOG" >&2
      [[ "$NET_TIMED_OUT" = "1" ]] && net_timeout_abort "push origin HEAD:$TRUNK" "$LAND_BASE" \
        "Whether the remote took this re-push is UNKNOWN; the next /ship re-fetches and decides."
      if [ "$(push_failure_kind "$(cat "$REPUSH_LOG")")" = "non-ff" ]; then
        # a sibling advanced trunk again inside the retry window — reconcilable. The next loop iteration's
        # verify fails (our head is not on the trunk) and drives another bounded reconcile; the attempt
        # counter still terminates a persistently-rejecting remote.
        echo "↻ ship-land: re-push non-ff inside the retry window — reconciling again next round." >&2
      else
        # NOT a race, so reconciling cannot help. Same exit 7 as the first push: nothing landed, tree
        # clean, backup ref intact. No attest_land here by design — _land_exit_trap attests EVERY
        # non-zero terminal exit, and this file's own header puts that rule in the trap and not at
        # the exit sites; the first push's exit 7 is silent for the same reason.
        rm -f "$REPUSH_LOG"
        # gate_bounded: SHIP_LAND_VERIFY_RETRIES — this branch IS that budget's expiry turned into an
        # event, which is the conversion this lint asks for. Reaching it costs no wait at all: git has
        # already returned a determinate verdict, and the refusal carries git's own output with it.
        # What stood here BEFORE was the standing state the lint exists to catch — a hook refusal
        # burned every retry silently and then exited 8 blaming a concurrent content-drop.
        echo "✗ ship-land: re-push was turned away inside the retry window, and git rejected NO ref for a fast-forward reason — NOT a race, so reconciling again cannot clear it. The party that turned it away is almost always the pre-push hook; its output is above, verbatim. Fix what it names, then re-run /ship. Backup ref ship/backup-* intact (exit 7)." >&2
        exit 7  # gate_bounded: SHIP_LAND_VERIFY_RETRIES — the retry budget's expiry, made into an event
      fi
    fi
    rm -f "$REPUSH_LOG"
  done

  # --- THE LAND IS PROVEN. Everything left is cleanup + bookkeeping, so the mutex ends HERE. ---
  # Hand the facts to the outer process and exit: land-lock's EXIT trap releases the moment we do,
  # and post_release_finish (see its header) runs the backup-ref reap, the stranded-sweep, the
  # attest and the post-land kick with NO lock held. That is the whole of P1 — the hold now covers
  # the race window this function opened it for, and nothing else.
  post_state_write "$LANDED_HEAD"
  exit 0
}

# ---- outer phase (preflight → launch locked child) -------------------------

# ---- P2 SHIFT-LEFT: the commit-time entry point ----------------------------
#
# THE DEFECT (land-architecture-100p §5 P2, §2.B): gate-red is 27%/14d → 39%/3d → 45% on the last
# day of ship-land invocations, and 89% of those invocations run no smoke at all, so the reds are
# STATICS AND RATCHETS. Each one is an agent-side diagnose-fix-rerun loop that NEVER TAKES THE
# LOCK — invisible to the lock ledger by construction — and each round costs a full 127-137s gate
# preceded by a fetch and a rebase. The verdict was reachable in the author's own tree, seconds
# after the edit, for the whole time it was instead being discovered at the land.
#
# THE ONE DESIGN RULE, and everything below follows from it: THIS IS NOT A SECOND AUTHORITY.
# It does not re-implement the rules, does not summarise them, does not pre-filter them. It calls
# run_gate — the same function, on the same range, with the same globals — and reports what it
# says. A separate implementation of a gate's rules is the defect this repo has paid for
# repeatedly (memory: enforcement-must-live-at-the-chokepoint), and a pre-filter that reuses the
# gate's own boundary rule can SHADOW it (memory: cost-gate-must-be-strictly-weaker). The
# shadowing proof here is structural rather than argued: there is no boundary rule to reuse,
# because the precheck decides nothing the land re-reads.
#
#   · It writes NO land.log row. A precheck is not a land attempt, and counting it as one would
#     poison the very denominator the P2 census panel reports (scripts/gate-red-census.sh).
#   · It claims no in-flight marker, writes no backup ref, files no failure-inbox row, takes no
#     lock, pushes nothing, and never rebases — so no land, its own or a sibling's, can observe
#     that it ran.
#   · The ONE thing it shares with a land is the P3 statics memo, and that sharing is exact rather
#     than approximate: gate-memo keys a verdict on the blob sha plus the checker's version and
#     records ONLY rc 0, so a precheck can hand a land a green it re-derived from identical bytes
#     with an identical checker, and can never hand it a red or suppress one. A precheck of a RED
#     tree records nothing at all. tests/gate-precheck.bats pins that direction.
main_precheck() {  # $1=trunk $2=working(0|1) $3=fetch(0|1)
  local TRUNK="$1" WORKING="$2" DO_FETCH="$3" BASE RANGE rc code
  PRECHECK_INDEX=""
  # The land traps are disarmed: every one of them exists to make a DYING LAND legible (attest the
  # kill, file the inbox row, release the marker), and a precheck that fired them on Ctrl-C would
  # write a land.log row for a land that never started — manufacturing exactly the phantom the
  # lifecycle work exists to prevent. gate_home_teardown is the only unwind this path can owe, and
  # it is idempotent and refuses to remove anything it did not create.
  trap - TERM HUP INT EXIT
  trap 'gate_home_teardown' EXIT
  LIFECYCLE_ROLE="precheck"
  ATTEST_SUPPRESS=1   # belt to the argv scan's braces — the contract is "no land.log row", stated twice
  GATE_PRECHECK=1
  IN_LAND_LOCK=0

  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"

  # OFFLINE BY DEFAULT, and that is the point of the entry point rather than a corner cut: a
  # commit-time check an author runs ten times an hour must cost seconds and must work on a plane.
  # The consequence is stated rather than hidden — the base is the local origin ref, so a precheck
  # gates against the trunk as this worktree last saw it, and the land gates against the trunk as
  # it is. --fetch closes that gap when the author wants it closed.
  if [[ "$DO_FETCH" = "1" ]]; then
    git fetch origin "$TRUNK" 2>/dev/null || echo "⚠ precheck: fetch failed — using the local origin/$TRUNK" >&2
  fi
  BASE="$(git merge-base "origin/$TRUNK" HEAD 2>/dev/null || true)"
  if [[ -z "$BASE" ]]; then
    echo "✗ precheck: cannot find a merge-base with origin/$TRUNK — is '$TRUNK' the right trunk? (use --trunk)" >&2
    exit 2
  fi

  if [[ "$WORKING" = "1" ]]; then
    # A BARE REV, not a range, and every consumer in run_gate already handles it: `git diff <rev>`
    # compares that rev to the WORKING TREE, so uncommitted and staged edits are in scope. This is
    # the true commit-time position — the author has not committed yet. `${range%%..*}` in the
    # smoke phase yields the rev itself, so the union-scope derivation degrades correctly too.
    RANGE="$BASE"

    # UNTRACKED FILES MUST BE IN SCOPE, and the first version of this entry point missed them —
    # caught by the land gate on this commit's own diff, which is the best possible way to find it.
    # `git diff` reports only files git already knows about, so a BRAND-NEW file was invisible to
    # every own-set the gate builds. That is not a corner: a new file is the commonest thing an
    # author has in hand at commit time, and it made the precheck green on a tree the land then
    # refused — the precise "clears a tree the land will refuse" failure this entry point exists to
    # rule out. Measured live: tests/gate-precheck.bats was untracked, precheck said GREEN, the land
    # said RED on that file's missing $HOME fixture.
    #
    # `git add -N` makes them visible to `git diff` — but the author's index is THEIRS, and a check
    # that stages things behind their back is a side effect, not a check. So the intent-to-add goes
    # into a THROWAWAY COPY of the index which every git command in the gate then reads through
    # GIT_INDEX_FILE. The real index is never opened for writing; a partially staged tree survives
    # untouched; and the copy dies with the process (see the trap above, extended here).
    local pc_idx real_idx untracked
    real_idx="$(git rev-parse --git-path index 2>/dev/null || true)"
    untracked="$(git ls-files --others --exclude-standard 2>/dev/null || true)"
    if [[ -n "$untracked" && -n "$real_idx" && -f "$real_idx" ]]; then
      pc_idx="$(mktemp "${TMPDIR:-/tmp}/ship-land-precheck-index.XXXXXX")" || pc_idx=""
      if [[ -n "$pc_idx" ]] && cp "$real_idx" "$pc_idx" 2>/dev/null; then
        PRECHECK_INDEX="$pc_idx"
        trap 'gate_home_teardown; [[ -n "${PRECHECK_INDEX:-}" ]] && rm -f "$PRECHECK_INDEX"' EXIT
        export GIT_INDEX_FILE="$pc_idx"
        # -N only: records the PATH, never the content, so nothing here can be committed by
        # accident even if this index were somehow reused.
        printf '%s\n' "$untracked" | while IFS= read -r u; do
          [[ -n "$u" ]] && git add -N -- "$u" 2>/dev/null
        done
        echo "  including $(printf '%s\n' "$untracked" | grep -c .) untracked file(s) via a throwaway index (yours is untouched)." >&2
      else
        # NAMED, never silent: a precheck that quietly skipped the new files would be reporting on
        # a tree the author does not have.
        echo "⚠ precheck: could not build a scratch index, so UNTRACKED files are NOT gated here." >&2
        echo "  git add them (or commit) and re-run, or the land may still red on a file this missed." >&2
      fi
    fi
  else
    RANGE="$BASE..HEAD"
    if [[ -z "$(git rev-list "$RANGE" 2>/dev/null)" ]]; then
      echo "✓ precheck: nothing to gate — origin/$TRUNK already contains HEAD. (Use --working to gate uncommitted edits.)"
      exit 0
    fi
  fi

  echo "→ precheck: the LAND GATE's statics + ratchets, run here — no lock, no push, no land.log row." >&2
  if [[ "$WORKING" = "1" ]]; then
    echo "  range: $RANGE (base → WORKING TREE; uncommitted and staged edits included)" >&2
  else
    echo "  range: $RANGE (base → HEAD; add --working to include uncommitted edits)" >&2
  fi
  rc=0
  run_gate "$RANGE" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    # THE SAME TRANSLATION THE LAND USES, character for character — gate_nonzero_code is what
    # splits a claim about the TREE (6) from a claim about the MACHINE (9). Re-deriving that split
    # here would be the second authority the header forbids, in the one place it would matter most.
    code="$(gate_nonzero_code "at precheck")"
    echo "✗ precheck: this tree would RED the land gate — arm(s): ${GATE_RED_WHY:-unattributed}." >&2
    echo "  Fix it here, in seconds, instead of discovering it after a fetch + rebase + full gate." >&2
    exit "$code"
  fi
  echo "✓ precheck: statics + all ratchet arms GREEN on $RANGE."
  echo "  This is the land gate's own verdict on this tree, minus the bats smoke phase (which the"
  echo "  land runs, and which is none/skipped on ~85% of lands — scripts/gate-red-census.sh)."
  echo "  A sibling landing before you can still move a repo-wide arm's input; re-run /ship as usual."
  exit 0
}

main_outer() {
  local DRY_RUN=0 TRUNK="" PRECHECK=0 WORKING=0 DO_FETCH=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=1; shift ;;
      --precheck) PRECHECK=1; shift ;;
      --working) WORKING=1; shift ;;
      --fetch) DO_FETCH=1; shift ;;
      --trunk) TRUNK="${2:-}"; shift 2 ;;
      --trunk=*) TRUNK="${1#--trunk=}"; shift ;;
      -h|--help) sed -n '2,48p' "$SELF"; exit 0 ;;
      *) echo "✗ ship-land: unknown argument '$1'" >&2; exit 2 ;;
    esac
  done
  [[ -z "$TRUNK" ]] && TRUNK="$(detect_trunk)"

  # REFUSED rather than silently ignored: --working and --fetch are precheck-only, and a land that
  # accepted them would be accepting an instruction it does not honour. That is the shape a later
  # reader mis-reads as "I asked for the working tree to be gated and it was".
  if [[ "$PRECHECK" != "1" ]] && { [[ "$WORKING" = "1" ]] || [[ "$DO_FETCH" = "1" ]]; }; then
    echo "✗ ship-land: --working / --fetch are --precheck options; a land always gates its committed range and always fetches." >&2
    exit 2
  fi
  # DISPATCHED HERE, before the first refusal below, and every one of them is deliberately skipped:
  # the shared-checkout refusal guards a PUSH (a precheck cannot push, and the shared checkout is
  # exactly where an author who has not made a worktree yet is standing — refusing them the cheap
  # check would send them to the expensive one); the dirty-tree refusal guards a LAND of unreviewed
  # bytes, whereas a dirty tree is the precheck's whole subject under --working.
  if [[ "$PRECHECK" = "1" ]]; then main_precheck "$TRUNK" "$WORKING" "$DO_FETCH"; fi

  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  # HERE, not in the trap — this is the earliest point in a real land where the worktree is
  # provably alive, and the whole mechanism is that the trap may run after it is not. See
  # LAND_MAIN_ROOT above for the four-duplicate-row measurement this line exists to stop.
  LAND_MAIN_ROOT="$(resolve_main_root "$REPO_ROOT")"
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

  # --- P4 defect 3: CLAIM THE WORKTREE (a second concurrent fire is refused, exit 11) ---
  # Placed HERE, and the position is the whole design: every refusal ABOVE is immediate,
  # author-visible feedback that files nothing (see land_failure_inbox); from this line on a land
  # has genuinely started, so the close protocol must read LANDING instead of 📦 and any non-zero
  # terminal exit — including the escalation PARK below — owes the operator an inbox row.
  inflight_claim

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

  # --- the locked child's handover slot (see post_state_write) ---
  # Keyed on THIS process, so two worktrees of one repo landing concurrently cannot collide on it
  # (they share a git common dir but never a pid). Removed at both ends — here in case a pid was
  # recycled onto a dead land's file, and again by post_release_finish on read. The prune covers
  # the only leak left: this process killed between the child's write and our read.
  SHIP_LAND_POST_STATE="$(post_state_path "$$")"
  export SHIP_LAND_POST_STATE
  # `.attested` rides the same slot and the same prune (the glob covers it) — see attest_land.
  rm -f "$SHIP_LAND_POST_STATE" "${SHIP_LAND_POST_STATE}.attested" 2>/dev/null || true
  find "$(dirname "$SHIP_LAND_POST_STATE")" -maxdepth 1 -name 'ship-land-post-*' -mtime +1 -delete 2>/dev/null || true

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
    meas_export
    "$LAND_LOCK" -- "$SELF" __locked "$TRUNK" "$DRY_RUN" "$GATE_BASE" "$GATE_HEAD"
    rc=$?
    # THE LOCK IS RELEASED THE INSTANT THAT RETURNS. Cleanup + attest run here, unlocked.
    child_attested_absorb
    if [[ "$rc" -eq 0 ]]; then post_release_finish "$TRUNK"; exit 0; fi
    if [[ "$rc" -ne 42 ]]; then exit "$rc"; fi   # a real failure (incl. land-lock's 75) — propagate
    # P0: THE STALE-GATE ROUND, ATTESTED — here, with the mutex already released (see the exit-42
    # site in main_locked for why not there). stage:"round" marks it non-terminal, so it counts in
    # the staleness census and in NO rate's denominator. ATTESTED is cleared afterwards because the
    # land is NOT over: the next round's terminal outcome still owes the ledger its own row.
    #
    # attest_refs runs HERE and not in the child for the same reason the row does: it is two git
    # forks, and out here they cost the fleet nothing. It makes the round replayable — WHICH base
    # and head went stale — and it cannot disturb postland-verify.sh's `author_sid` lookup, the
    # only other parser of these rows: that keys on the LANDED sha, which a pre-re-rebase round row
    # never carries, and it reads `sid`, which is identical on both rows anyway.
    attest_refs "$GATE_BASE"
    attest_land "n/a" "n/a" "n/a" 42 "round"
    ATTESTED=0
    echo "↻ ship-land: optimistic round ${round}/${ROUNDS} invalidated (sibling land mid-gate) — re-gating the new final tree unlocked." >&2
  done

  # --- rounds exhausted (sustained contention) or SHIP_LAND_GATE_ROUNDS=0: guaranteed
  #     progress — rebase + re-gate INSIDE the lock, STATICS + RATCHETS ONLY (run_gate refuses to
  #     start bats when IN_LAND_LOCK=1, in either lane). A held mutex stops further pipeline
  #     movement, so this round cannot be invalidated; the difference from v1 is that it now
  #     costs seconds instead of the 3h36m lock hold that jammed the fleet. ---
  [[ "$ROUNDS" -gt 0 ]] && echo "→ ship-land: ${ROUNDS} optimistic round(s) exhausted — falling back to the in-lock STATICS-only re-gate (guaranteed progress; nothing heavy enters the lock)." >&2
  # NOT `exec` any more, deliberately: exec'ing away left no outer process to run the post-release
  # phase, so this lane would have kept the sweep inside the lock — the exact defect, surviving in
  # the one lane that only fires under sustained contention, i.e. when the fleet can least afford
  # an 87s hold. Same handover, same finish, one process deeper.
  meas_export
  "$LAND_LOCK" -- "$SELF" __locked "$TRUNK" "$DRY_RUN" "" ""
  rc=$?
  child_attested_absorb
  [[ "$rc" -eq 0 ]] && post_release_finish "$TRUNK"
  exit "$rc"
}

# ---- dispatch --------------------------------------------------------------

# P4 defect 1 — INSTALLED BEFORE ANY WORK, in BOTH roles. The locked child is a separate process
# behind land-lock, and a process-group signal reaches it too; it attests its own death (the
# handler knows its role) while ownership of the marker and the inbox stays with the outer, which
# is the process that knows the re-land command.
trap _land_exit_trap        EXIT
trap '_land_sig_verdict TERM 15' TERM
trap '_land_sig_verdict HUP 1'   HUP
trap '_land_sig_verdict INT 2'   INT

if [[ "${1:-}" = "__locked" ]]; then
  shift
  LIFECYCLE_ROLE="locked"
  validate_lane_scope  # after the traps: an exit 2 here now attests, like every other terminal exit
  main_locked "$@"     # always exits internally
else
  validate_lane_scope
  main_outer "$@"      # exec's the locked child, or exits on a preflight refusal
fi
