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
#   wrap-ledger.sh --goal     → the ◎ goal-liveness line ALONE, or nothing (see § GOAL)
#
# ── RUNG (worst-open, priority ⛔ > 📤 > 🔧 > 📦 > 🚀 > 👤 > ✅) ──
#   This ledger computes SIX rungs {⛔, 🔧, 📦, 🚀, 👤, ✅}. Only 📤 (out-of-context) remains
#   model-state — nothing on disk knows how full a context window is — so only 📤 is overlaid by the
#   model; when present it dominates everything below it. Derivation:
#     ⛔  an open class-C decision packet THIS SESSION filed — a human-gated fork, unresolved
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
#   ⛔ (2026-08-07): the HIGHEST-priority rung was the ONLY one with no sensor, and "the model
#   overlays it" is not a mechanism — it is the absence of one. Measured: a close rendered
#   "✅ SAFE TO CLOSE — nothing of mine is open", TRUE over every git fact this script reads, while
#   the model was holding a blocking operator decision, which it then demoted to paragraph 4 of its
#   own prose; the operator had to spend a round-trip asking what the decision even was. A rung that
#   outranks every other one cannot be left to the same prose the rung exists to discipline.
#   The store already existed: `cc-decide` writes one packet per decision carrying `session_sid`, so
#   ⛔ is derived exactly the way 👤 is — `cc-decide list --open --class C --json`, counting ONLY
#   rows whose `.session_sid` equals THIS session's id. cc-decide stays the arbiter of what "open"
#   means (the predicate is its jq, never re-implemented here — MEMORY.md
#   make-the-actuator-the-arbiter).
#   CLASS C ONLY. A class-B packet carries a default that FIRES at its deadline if nobody vetoes, so
#   it resolves itself and is not a blocker; C is human-gated and waits forever (hooks/
#   operator-readout.sh:53 draws the same line). SESSION-SCOPED for the 👤 reason, at greater force:
#   this machine standingly carries ~21 open decisions, and a top-priority rung counting those would
#   fire at EVERY close forever — an alarm that always fires carries exactly as many bits as one
#   that cannot (MEMORY.md alarm-polarity). Unresolvable session ⇒ BLOCKED=0 + BLOCKED_SRC=none;
#   unreadable store ⇒ BLOCKED=0 + BLOCKED_SRC=error. An unresolvable sensor NEVER manufactures a
#   rung — the same law as YOURS_SRC=none and LIVE_SRC=unknown.
#   ITS COST IS PAID AT EVERY CLOSE, deliberately. 👤 and 🚀 are computed only on the ✅-eligible
#   path, because a worse rung already governs there and the read cannot change the answer. ⛔
#   outranks 🔧, so that trick is unavailable to it: the answer is unknown until it is asked. One
#   bounded fork (`WRAP_DECIDE_TIMEOUT_S`, default 5s) per turn close is the price of a rung that
#   outranks everything — which is why it is ONE fork and not two, and why BLOCKED_SRC=skip is
#   unreachable here by construction.
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
#   PAST the converge budget is news: WRAP_LIVE_BUDGET_COMMITS (25) or WRAP_LIVE_BUDGET_MIN (360,
#   measured from the commit the LIVE LAYER IS ON — NOT from this session's HEAD; the two are
#   different quantities and this sentence asserted both until 2026-08-26, see compute_live_layer),
#   whichever trips FIRST — mirroring CC_DEPLOY_MAX_LAG_COMMITS / CC_DEPLOY_MAX_LAG_HOURS in
#   deploy-live.sh, now on the same clock as well as the same name. Within budget the fact is
#   ATTACHED to the ✅ readout
#   ("live layer converging") instead of spending a rung. A FAILED migration
#   ($CC_MIGRATIONS_STATE/failed/*.json — the converger reporting it could NOT put a landed
#   conclusion into settings.json / a plist / PATH) trips 🚀 immediately, with no budget: no tick
#   clears it, so it is not a timing artifact.
#
#   …BUT THE BUDGET IS AN EDIT'S BUDGET, AND AN ADD IS NOT AN EDIT (2026-08-09, backlog
#   99b715f31a98). Both sentences above — "converging", "it will be current in a tick" — are true
#   only of a file that ALREADY HAS ITS LINK. ~/.claude/{hooks,hooks/lib,commands,scripts,bin} are
#   real dirs of PER-FILE symlinks (deploy-parity-assert.sh's existence leg states the same fact for
#   its own question), so an EDITED file rides its link: at lag N the box runs that file's OLDER
#   version, degraded but present, and the fast-forward alone makes it current. A file the landed
#   diff ADDS is not stale — it is ABSENT. There is no link, and every consumer that resolves it
#   sibling-first into the checkout misses too. The guard forms in this tree are `[ -f x ] && . x`
#   and `command -v fn >/dev/null && fn …`, both of which are SILENT skips, so the feature does not
#   fail — it does not exist. That is inert at lag 1, and no number of commits or minutes makes it
#   less so. Measured: scripts/lib/pane-spawn-log.sh landed with 20 instrumented spawn sites; this
#   ledger read "BEHIND 7, within budget (25)" and rendered a plain OK while every
#   `command -v cc_log_pane_spawn` call site short-circuited to nothing.
#   So LIVE_ADDS > 0 breaches at lag ≥ 1, with no budget. It does NOT become an always-fires alarm:
#   28.5% of the last 200 trunk commits add a file (measured), the breach lasts only until the live
#   layer carries them, and CLAUDE.md's own 🚀 disposition has the AGENT run the converger and
#   re-read — so a healthy box self-clears it within one close. It persists exactly as long as a
#   real converger outage does, which is the state it exists to report.
#
#   ⚠️ BUT "self-clears within one close" IS CONDITIONAL, AND THE CONDITION IS NOT THE ADD
#   (measured 2026-08-24, backlog b79591064f75 — closed REFUTED). That row read this asymmetry as a
#   deadlock: this ledger breaches on an ADD, while deploy-live.sh cannot see adds at all (0
#   `diff-filter=A` sites, 0 `LIVE_ADDS`; its budget is LAG_COMMITS/LAG_HOURS only) — concluding the
#   🚀 rung "names a converger that DETERMINISTICALLY declines", so CLAUDE.md's
#   no-unreachable-✅ guarantee fails. Both halves are TRUE and the conclusion does NOT follow.
#   deploy-live advances iff it sets $TARGET, and $TARGET comes from T1 (newest GREEN tree that
#   DESCENDS from live HEAD) or T1H (an OFF-BOX hermetic green with no on-box RED). Neither reads
#   added files. Adds and the decline are INDEPENDENT axes; the row's single exhibit carried both
#   and read co-presence as causation — its own quoted refusal names the real cause, "no GREEN tree
#   is a DESCENDANT of live HEAD".
#   So do NOT "give deploy-live the same add-awareness" to make the two agree. The lag budget's only
#   POSITIVE effect is arming T2 at deploy-live.sh:1621 — the DEGRADED door that takes the newest
#   NOT-RED commit and advances under a page recording an UNVERIFIED deploy. Tripping that on every
#   add (28.5% of trunk commits, above) would make absence-of-evidence the DEFAULT deploy path.
#   And do NOT suppress the prescription here either: this ledger never reads the green ladder, so
#   it cannot know the converger will decline, and silencing the command would withhold a correct
#   drivable action in every case where T1/T1H is non-empty.
#   What the row DID surface: a persistent breach here need not be a converger OUTAGE. VERIFIER
#   FAMINE produces the same picture, and deploy-live pages that under its own name (:464).
#
#   LADDER POSITION: 📦 and 🚀 are the two "the value is not where it needs to be" rungs, in store
#   order branch → trunk → live, so 🚀 sits directly below 📦. 👤 asks a different question (the
#   OPERATOR's queue) and ranks below both.
#
# ── § GOAL — the liveness ORACLE (E5, docs/research/goal-safe-2way-comms-2026-08-13.md §8/§9 B5) ──
#   REPORTED, NEVER A RUNG. A live `/goal` is a normal state of a working session, so a rung on it
#   would fire at every close of every goal-armed session — the alarm-polarity law that already
#   bounds 👤, ⛔ and 🚀 here. What was missing is not a verdict but a MEASUREMENT: §2 measured
#   84 goal sessions, 47 of them with ZERO evaluations, and could not decompose that class —
#   "a goal deferred behind a REAL subagent/build is A2 working as designed", a goal starved behind
#   a parked 4-hour watcher is the defect, and NOTHING ON DISK told them apart. Evaluation-liveness
#   had no oracle, so neither the residual nor any fix to it could be measured. Two fields answer
#   it: how many NON-SENTINEL `goal_status` attachments (evaluations) exist since the last arm, and
#   what the most recent one said. `0 evals · armed 142m ago` IS the starvation pole, at the close
#   where it can still be acted on, instead of in a 3-day corpus sweep that comes too late.
#   Fields: GOAL_SRC (none · error · absent · live · cleared · failed) · GOAL_EVALS · GOAL_LAST
#   (none · arm · unmet · met · clear · failed) · GOAL_LAST_T (HH:MM local, `-` if unparseable) ·
#   GOAL_AGE_MIN · GOAL_LINE (the ◎ line; NON-EMPTY only for a LIVE goal, per the same law).
#   The record dictionary is NOT re-implemented here — hooks/lib/goal-state.sh::goal_liveness owns
#   it, shared with goal_live_condition's consumers, so two readers of the same records cannot
#   drift (MEMORY.md make-the-actuator-the-arbiter).
#   FAIL DIRECTION: no transcript ⇒ `none`; unreadable/no-jq/lib-too-old ⇒ `error`; readable with
#   no goal records ⇒ `absent`. `absent` is a POSITIVE finding and is never manufactured from a
#   read that did not happen — the same law as YOURS_SRC=none and LIVE_SRC=unknown.
#
# ── LAW ── fail-LOUD, never fail-silent-open: outside a git repo (or on a read error) this exits
#   non-zero with a stderr note and NEVER prints RUNG=✅. A consumer that can't get a ledger must
#   treat that as "cannot confirm", not as "complete". Pure-read of the REPO: the only bytes this
#   writes are its own memo under TMPDIR (below) — which is why the live-layer read never fetches
#   (see compute_live_layer).
#
# Env seams (tests): WRAP_TRUNK · WRAP_DOD_DIR · WRAP_DOD_FILE · WRAP_GATE_GREEN ·
#                    WRAP_SESSION_ID · CC_BACKLOG_BIN · CC_DECIDE_BIN · WRAP_LIVE_REPO ·
#                    WRAP_LIVE_BUDGET_COMMITS · WRAP_LIVE_BUDGET_MIN · CC_MIGRATIONS_STATE ·
#                    WRAP_BACKLOG_TIMEOUT_S · WRAP_DECIDE_TIMEOUT_S · WRAP_TRANSCRIPT ·
#                    WRAP_GOAL_TIMEOUT_S · WRAP_PROJECT_ROOTS ·
#                    WRAP_CACHE · WRAP_CACHE_DIR · WRAP_CACHE_WAIT_MS · WRAP_CACHE_WAIT_TRIES ·
#                    WRAP_CACHE_LOCK_STALE_S
set -uo pipefail

MODE="readout"
SESSION_FLAG=""
TRANSCRIPT_FLAG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --machine) MODE="machine" ;;
    --full)    MODE="full" ;;
    --goal)    MODE="goal" ;;
    --readout|"") MODE="readout" ;;
    --session) shift; SESSION_FLAG="${1:-}" ;;
    --session=*) SESSION_FLAG="${1#--session=}" ;;
    --transcript) shift; TRANSCRIPT_FLAG="${1:-}" ;;
    --transcript=*) TRANSCRIPT_FLAG="${1#--transcript=}" ;;
    -h|--help) printf 'usage: wrap-ledger.sh [--machine|--full|--readout|--goal] [--session <sid>] [--transcript <path>]\n'; exit 0 ;;
    *) printf 'wrap-ledger: unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

# ══ THE MEMO — one ledger per Stop EVENT, keyed on the transcript ═══════════════════════════════
# (scaling-bottlenecks-2026-08-09 §5 P0-4; design docs/research/scaling-bottlenecks-2026-08-09/
#  04-occupancy-b.md §6. Backlog 9414dfb87233.)
#
# THE COST IT REMOVES, measured: this script is ~180 ms CPU / 19 git subprocesses per run, and
# SEVEN Stop-hook call sites run it on EVERY turn close (session-continue ×2, completion-assert,
# anti-deference-nudge, boundary-handoff, operator-readout ×2) — ~1.26 s of CPU and ~133 git
# subprocesses per close, per session, forever. The seven are not independent queries at arbitrary
# times: they are ONE event, dispatched CONCURRENTLY inside a single ~45 ms window. Within one Stop
# they SHOULD observe one snapshot; today each takes its own and they can already disagree.
#
# TWO PRIOR DESIGNS DIED HERE. Both are structurally excluded, not tuned around:
#
#   FAILURE 1 (9adc5120) — benchmarked SEQUENTIALLY (60 → 27 git, "2.22×") and shipped as a
#   REGRESSION. Six consumers arriving inside 45 ms all MISS together, all compute, and the six
#   fingerprints are pure added cost: measured 72 git vs 60 uncached — 20% WORSE on the first Stop
#   after any tree change, i.e. the common case. ⇒ a cache may never make the uncached path worse
#   than uncached, and that is a property of the ARRIVAL PATTERN, not of the hit rate. The fix,
#   retained below: a bounded SINGLE-FLIGHT — the first caller takes a `mkdir` lock and computes,
#   the rest take a small bounded number of SHORT sleeps and re-read the atomically `mv`d result.
#   Never a poll loop: `sleep` is a fork here, and a 40 ms poll over a 2 s bound forks ~50× per
#   loser and costs more than the git calls it saves.
#
#   (A THIRD design — "split the computation, not the cache": cache the git-derived fields under a
#   (HEAD, porcelain) key, re-run the store forks per caller, re-derive RUNG — was RECORDED as the
#   fallback in CONCURRENCY_PROGRAM.md §S6.4 and is REFUTED, 2026-08-12, backlog 0b4d4e8a1889.
#   That key is blind to the live-layer arm, which is 8 of the 19 git calls and reads a DIFFERENT
#   repo: the live checkout's HEAD and $CC_MIGRATIONS_STATE/failed both move under a byte-identical
#   (HEAD, porcelain) — measured both ways, a stale 🚀 and a FALSE ✅. It is FAILURE 2 one rung down.
#   Controls: tests/wrap-ledger-memo.bats § 7; cost arm SPLIT FLOOR in wrap-ledger-memo-bench.sh.)
#
#   FAILURE 2 (5da21949) — WITHDRAWN because its key could not see a real change. It keyed on the
#   CONTENT of the operator stores via their directory mtimes, and A DIRECTORY'S MTIME DOES NOT
#   MOVE WHEN A FILE'S CONTENT CHANGES: flipping a class-C packet open→vetoed edits an existing
#   file, so the memo served the pre-veto ⛔ over a decision the operator had already resolved — on
#   the HIGHEST-priority rung. Its own 18-test suite (4 mutation controls) was green; the CONSUMER
#   suite (tests/wrap-ledger.bats) went 3 red. A content digest would see it, but find+stat+cksum
#   over 115 decision files is 16.46 ms — a NEW unbounded per-Stop cost added by a change whose
#   whole purpose is removing unbounded per-Stop cost.
#
# THE KEY, therefore, is scoped to the EVENT and never to the content:
#
#     key = (transcript path ⊕ its mtime,size) ⊕ session-id inputs ⊕ cwd ⊕ the env seams
#
#   · NO TTL — the key is not time-derived, so there is no inert-bound to tune.
#   · NO STORE FINGERPRINT — an operator resolving a decision happens BETWEEN turns, and a new turn
#     always appends to the transcript ⇒ new key ⇒ a compute. That is what makes the transcript a
#     sound proxy where a store directory's mtime was not.
#   · ABSENT KEY ⇒ NO CACHE. Not "cache with a default": no `--transcript`/$WRAP_TRANSCRIPT, an
#     unstattable transcript, or no `cksum` ⇒ compute, every time. CLI, `/wrap` and the bats suites
#     pass no transcript, so they are uncached BY CONSTRUCTION rather than by tuning — which is why
#     tests/wrap-ledger.bats (the suite that refuted FAILURE 2) cannot be affected by this at all.
#   · MACHINE MODE ONLY — --readout/--full are human surfaces, called once, and a cached block is
#     not what either of them prints.
#   · RACE DEGRADES, NEVER LIES — if the harness appends mid-event, consumers compute different
#     keys and pay two computes. Never a wrong rung.
#   · THE SEAMS ARE IN THE KEY because two consumers do NOT call this identically:
#     completion-assert passes `--session $SID`, the other six do not, and the resolved SID changes
#     YOURS/BLOCKED. Keying on the raw INPUTS (all three session sources, not the resolved one)
#     cannot drift out of step with the resolution order below the way a duplicated precedence
#     would.
#   · THE FULL KEY IS STORED IN THE FILE AND COMPARED ON READ, so a cksum collision costs a miss,
#     never a wrong ledger.
#
# Kill switch: WRAP_CACHE=off|0|no ⇒ never read, never write (the benchmark's control arm).
WL_KEY=""; WL_FILE=""; WL_LOCK=""; WL_DIR=""; WL_LOCK_HELD=0
WL_TRANSCRIPT="${TRANSCRIPT_FLAG:-${WRAP_TRANSCRIPT:-}}"
# The transcript as an INPUT, kept out of the cache kill-switch's reach. $WL_TRANSCRIPT is a
# CACHE-KEY variable and `WRAP_CACHE=off` BLANKS it (below) — so a term that read the transcript
# through it would answer a different question under the benchmark's control arm than under the
# ordinary one, which tests/wrap-ledger-memo.bats §2 catches as a byte-difference between the
# cached and uncached ledgers. Caching is about how often a fact is recomputed, never about which
# facts exist.
GOAL_TRANSCRIPT="$WL_TRANSCRIPT"

# "<mtime> <size>" for $1, or EMPTY when that cannot be read as exactly two integers. BSD stat
# first (this fleet is macOS), GNU second — and VALIDATED rather than trusted, because GNU `stat -f`
# is a different flag entirely (--file-system) and prints a multi-line filesystem block on stdout
# while returning non-zero. Trusting rc or non-emptiness there would key every session on one
# constant string, which is precisely the never-invalidates failure this design exists to avoid.
_wl_stat_ms() {
  local out m z
  out="$(stat -f '%m %z' "$1" 2>/dev/null || true)"
  read -r m z <<WLSTAT
$out
WLSTAT
  case "${m:-}" in ''|*[!0-9]*) m="" ;; esac
  case "${z:-}" in ''|*[!0-9]*) z="" ;; esac
  if [ -z "$m" ] || [ -z "$z" ]; then
    out="$(stat -c '%Y %s' "$1" 2>/dev/null || true)"
    read -r m z <<WLSTAT2
$out
WLSTAT2
    case "${m:-}" in ''|*[!0-9]*) m="" ;; esac
    case "${z:-}" in ''|*[!0-9]*) z="" ;; esac
  fi
  [ -n "$m" ] && [ -n "$z" ] || return 1
  printf '%s %s' "$m" "$z"
}

# ONE fork (cksum, POSIX, on every box this runs on) to turn the key into a filename. The pure-bash
# alternative was measured at 5.1 ms for a 308-char key — nearly the whole per-consumer budget —
# against cksum's 3.0 ms. No cksum ⇒ no key ⇒ no cache, per the absent-key law.
_wl_digest() {
  local d
  d="$(printf '%s' "$1" | cksum 2>/dev/null | tr -cd '0-9 ' | tr ' ' '-')" || return 1
  d="${d%-}"
  [ -n "$d" ] || return 1
  printf '%s' "$d"
}

# Serve: rc 0 and the body on stdout IFF the file exists AND its stored key is byte-equal to ours.
# Read in pure bash — a `cat` here would spend a fork on the path whose entire point is not
# spending them.
_wl_cache_serve() {
  local first line body="" got=0
  [ -n "$WL_FILE" ] && [ -s "$WL_FILE" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$got" -eq 0 ]; then first="$line"; got=1; continue; fi
    body="${body}${line}
"
  done < "$WL_FILE"
  [ "${got:-0}" -eq 1 ] || return 1
  [ "${first:-}" = "#WLKEY $WL_KEY" ] || return 1
  [ -n "$body" ] || return 1
  printf '%s' "$body"
}

# Store: write-to-temp + atomic `mv`, so a reader can never see a half-written ledger. Every
# failure is silent and harmless — the caller has already printed its answer.
_wl_cache_store() {
  local tmp
  [ -n "$WL_FILE" ] && [ -n "$WL_DIR" ] || return 0
  # $WL_DIR, never `dirname "$WL_FILE"` — three dirname calls is three forks on the path whose
  # entire purpose is not spending them.
  [ -d "$WL_DIR" ] || mkdir -p "$WL_DIR" 2>/dev/null || return 0
  tmp="$(mktemp "$WL_DIR/.w.XXXXXX" 2>/dev/null)" || return 0
  { printf '#WLKEY %s\n' "$WL_KEY"; printf '%s\n' "$1"; } > "$tmp" 2>/dev/null \
    || { rm -f "$tmp" 2>/dev/null; return 0; }
  mv -f "$tmp" "$WL_FILE" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  # Bound the dir on the MISS path only (one fork, paid by a caller already spending 19 git calls).
  # Every event mints its own key, so nothing here is ever reused and without this the dir grows for
  # the life of the box. LOCK DIRS ARE SWEPT TOO: a winner that dies leaves one behind, and since no
  # later caller can ever present that dead event's key, nothing else would ever clear it.
  find "$WL_DIR" -mindepth 1 -maxdepth 1 -mmin +240 \( -type f -o -name '*.lock' \) \
       -exec rm -rf {} + 2>/dev/null || true
  return 0
}

_wl_lock_release() {
  [ "$WL_LOCK_HELD" -eq 1 ] || return 0
  WL_LOCK_HELD=0
  rmdir "$WL_LOCK" 2>/dev/null || rm -rf "$WL_LOCK" 2>/dev/null || true
}

# rc 0 iff the lock dir is older than the stale bound — i.e. its winner died mid-compute. Costs two
# forks and is asked ONLY after a wait already failed, which is the rare path.
_wl_lock_stale() {
  local now ms lm
  now="$(date +%s 2>/dev/null || echo 0)"
  case "$now" in ''|*[!0-9]*) return 1 ;; esac
  [ "$now" -gt 0 ] || return 1
  ms="$(_wl_stat_ms "$WL_LOCK")" || return 1
  lm="${ms%% *}"
  [ $((now - lm)) -gt "${WRAP_CACHE_LOCK_STALE_S:-30}" ]
}

case "${WRAP_CACHE:-on}" in off|0|no|OFF|NO) WL_TRANSCRIPT="" ;; esac
if [ "$MODE" = "machine" ] && [ -n "$WL_TRANSCRIPT" ]; then
  _wl_ms="$(_wl_stat_ms "$WL_TRANSCRIPT")" || _wl_ms=""
  if [ -n "$_wl_ms" ]; then
    # Every input that can change the answer, in one string. The seams are the ones the header's
    # "Env seams" line lists — a caller that overrides one is asking a different question and must
    # not be served another caller's.
    _wl_k="v1|$WL_TRANSCRIPT|$_wl_ms|$PWD|$SESSION_FLAG|${WRAP_SESSION_ID:-}|${CLAUDE_SESSION_ID:-}"
    _wl_k="$_wl_k|${WRAP_TRUNK:-}|${WRAP_DOD_DIR:-}|${WRAP_DOD_FILE:-}|${WRAP_GATE_GREEN:-}"
    _wl_k="$_wl_k|${CC_BACKLOG_BIN:-}|${CC_DECIDE_BIN:-}|${CC_CUSTODY_BIN:-}|${CC_CUSTODY_DIR:-}"
    _wl_k="$_wl_k|${WRAP_LIVE_REPO:-}|${WRAP_LIVE_BUDGET_COMMITS:-}|${WRAP_LIVE_BUDGET_MIN:-}"
    _wl_k="$_wl_k|${CC_MIGRATIONS_STATE:-}|${WRAP_LAND_INFLIGHT_LIB:-}"
    if _wl_d="$(_wl_digest "$_wl_k")"; then
      WL_DIR="${WRAP_CACHE_DIR:-${TMPDIR:-/tmp}/cc-wrap-ledger.${UID:-0}}"
      # The dir must exist BEFORE the single-flight `mkdir` lock, or the lock cannot be taken and
      # EVERY caller becomes a loser: measured, that is six waiters that all time out and all
      # compute — 84 git and 2.8 s of wall where uncached is 84 git and 0.48 s, i.e. FAILURE 1
      # rebuilt with sleeps on top. `[ -d ]` is a builtin, so this forks once per box, not per call.
      [ -d "$WL_DIR" ] || mkdir -p "$WL_DIR" 2>/dev/null || true
      if [ -d "$WL_DIR" ]; then
        WL_KEY="$_wl_k"
        WL_FILE="$WL_DIR/m-$_wl_d"
        WL_LOCK="$WL_FILE.lock"
      fi
    fi
  fi
fi

if [ -n "$WL_KEY" ]; then
  if _wl_cache_serve; then exit 0; fi
  # SINGLE-FLIGHT (the FAILURE-1 fix). Fail-open at EVERY branch: cannot lock ⇒ wait once, then
  # compute; waited out and still nothing ⇒ compute; a corpse ⇒ clear it and compute. Nothing here
  # can make a caller wait unboundedly, and nothing here can stop a caller answering.
  if mkdir "$WL_LOCK" 2>/dev/null; then
    WL_LOCK_HELD=1
    trap _wl_lock_release EXIT
  else
    # A FIXED wait cannot be right at both ends and a POLL is the fork bomb the header rejects, so
    # the sleeps DOUBLE: 50, 100, 200, 400 ms — ≤4 forks for a ≤750 ms bound. Measured, six
    # concurrent callers: a flat 3 × 100 ms woke every loser BEFORE the winner finished, so all six
    # computed (114 git — the FAILURE-1 shape, with 2× the wall on top). The early rungs cover a
    # fast box, the late ones a contended one, and 4 forks is a rounding error against the 19 git
    # calls a compute spends.
    # THE BOUND IS A WALL-TIME DECISION, and it is the one real trade this design makes. A longer
    # ladder holds the CPU win when the winner is slow; a shorter one caps how much WALL a loser can
    # add to a Stop that is already the felt-lag hot spot (3.7 s p50). 750 ms ≈ the uncached cost of
    # this whole script under six-way contention, so the worst case degrades to "uncached, plus the
    # wait" — never to an unbounded hold. Tunable, deliberately: a box where the winner routinely
    # overruns 750 ms wants more rungs, not fewer.
    _wl_tries="${WRAP_CACHE_WAIT_TRIES:-4}"
    case "$_wl_tries" in ''|*[!0-9]*) _wl_tries=4 ;; esac
    _wl_ms_wait="${WRAP_CACHE_WAIT_MS:-50}"
    case "$_wl_ms_wait" in ''|*[!0-9]*) _wl_ms_wait=50 ;; esac
    while [ "$_wl_tries" -gt 0 ]; do
      printf -v _wl_sleep '%d.%03d' "$((_wl_ms_wait / 1000))" "$((_wl_ms_wait % 1000))"
      sleep "$_wl_sleep" 2>/dev/null || true
      if _wl_cache_serve; then exit 0; fi
      _wl_tries=$((_wl_tries - 1))
      _wl_ms_wait=$((_wl_ms_wait * 2))
    done
    # The winner overran the wait or died. Clear a provably stale lock so the NEXT event does not
    # queue behind a corpse, then compute — never wait behind one.
    if _wl_lock_stale; then rmdir "$WL_LOCK" 2>/dev/null || rm -rf "$WL_LOCK" 2>/dev/null || true; fi
  fi
fi

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
# `git status --porcelain` IS THE RIGHT READ — do not "optimise" it to plumbing (2026-08-07,
# backlog 1162f51b1cf3, which claimed this line reads the stat bit and inflates the count).
# It does not. status REFRESHES: on a stat-mismatched entry git re-hashes the file and compares
# the OID, so byte-identical-but-touched files report CLEAN. Measured on git 2.54.0 with a
# positive control — `git diff-index` saw 10 files at the instant this saw 0, and that held under
# a stale index.lock and a read-only .git. Two rejected "fixes", both worse than the non-bug:
#   · `git update-index --refresh` — a strict NO-OP; status already refreshes and writes the index
#     back, so this only adds a fork to every Stop hook.
#   · `git diff --quiet` / `git diff --name-only` — a REGRESSION; both compare worktree against
#     index and are blind to UNTRACKED and STAGED-but-uncommitted files, i.e. they would report a
#     clean tree over unsaved work. That is the false ✅ this ledger exists to prevent.
# Pinned by tests/wrap-ledger.bats § "DIRTY IS CONTENT-TRUTHFUL, NOT THE STAT BIT" (3 cases, each
# mutation-verified to go red against exactly these two substitutions).
PORC="$(git status --porcelain 2>/dev/null || true)"
DIRTY_N="$(printf '%s' "$PORC" | grep -c . 2>/dev/null || echo 0)"; case "$DIRTY_N" in ''|*[!0-9]*) DIRTY_N=0 ;; esac
DIRTY=0; [ "$DIRTY_N" -gt 0 ] && DIRTY=1

# ── Ahead / unlanded-by-content ──
AHEAD=0; CHERRY=0; SHAS=""
if [ -n "$TRUNK" ]; then
  AHEAD="$(git rev-list --count "$TRUNK"..HEAD 2>/dev/null || echo 0)"; case "$AHEAD" in ''|*[!0-9]*) AHEAD=0 ;; esac
  # git cherry prints '+ <sha>' for commits whose patch is NOT present upstream (content-absent).
  if git cherry "$TRUNK" HEAD 2>/dev/null | grep '^+ ' >/dev/null; then CHERRY=1; fi
  SHAS="$(git rev-list --abbrev-commit "$TRUNK"..HEAD 2>/dev/null | head -5 | tr '\n' ' ' | sed 's/ *$//' || true)"
fi
UNLANDED=0; { [ "$AHEAD" -gt 0 ] || [ "$CHERRY" -eq 1 ]; } && UNLANDED=1

# ── LAND IN FLIGHT (land-architecture-100p §5 P4, defect 3) ──
# UNLANDED is true for the WHOLE duration of a land, not only before one — a land is minutes long
# and its only workable shape is backgrounded, so the close protocol routinely runs mid-flight and
# rendered "📦 … /ship to land it" as the one command over a land that was already running. The
# marker inverts that instruction; it never invents a landed state (📦 still outranks ✅, the
# commits really are unlanded, and the certificate stays unreachable). ONE reader for the predicate,
# shared with the producer — never a second copy (memory: make-the-actuator-the-arbiter).
LANDING=0; LANDING_PID=""; LANDING_AGE=0
_wl_lil="${WRAP_LAND_INFLIGHT_LIB:-$(dirname "$0")/../hooks/lib/land-inflight.sh}"
[ -f "$_wl_lil" ] || _wl_lil="$HOME/.claude/hooks/lib/land-inflight.sh"
if [ -f "$_wl_lil" ]; then
  # shellcheck source=../hooks/lib/land-inflight.sh
  # shellcheck disable=SC1091
  . "$_wl_lil" 2>/dev/null || true
  if _wl_live="$(land_inflight_live . 2>/dev/null)" && [ -n "$_wl_live" ]; then
    LANDING=1
    LANDING_PID="${_wl_live%% *}"
    LANDING_AGE="$(( $(date +%s) - $(printf '%s' "$_wl_live" | cut -d' ' -f2) ))"
  fi
fi

# ── Gate-green marker: green (== HEAD) · stale (present, ≠ HEAD) · none (absent) ──
GATE_FILE="${WRAP_GATE_GREEN:-$(git rev-parse --git-common-dir 2>/dev/null)/gate-green}"
GATE="none"
if [ -f "$GATE_FILE" ]; then
  GATE_SHA="$(head -1 "$GATE_FILE" 2>/dev/null | tr -d '[:space:]' || true)"
  if [ -n "$GATE_SHA" ] && [ "$GATE_SHA" = "$HEAD_SHA" ]; then GATE="green"; else GATE="stale"; fi
fi

# ── Frozen-DoD remainder (unchecked "- [ ]" items). Absent ⇒ reported, never silently ✅. ──
# Resolution = hooks/lib/dod-path.sh (CLOSE_INTEGRITY W3): repo-identity key with legacy
# path-hash read-fallback, shared with the producer so the two cannot drift. The inline fallback
# preserves the exact legacy formula for a live layer that has not yet linked the lib.
_wl_dplib="$(dirname "$0")/../hooks/lib/dod-path.sh"
[ -f "$_wl_dplib" ] || { _wl_dpt="$0"; [ -L "$_wl_dpt" ] && _wl_dpt="$(readlink "$_wl_dpt")"
  _wl_dplib="$(cd "$(dirname "$_wl_dpt")" 2>/dev/null && pwd)/../hooks/lib/dod-path.sh"; }
[ -f "$_wl_dplib" ] || _wl_dplib="$HOME/.claude/hooks/lib/dod-path.sh"
# shellcheck source=../hooks/lib/dod-path.sh
# shellcheck disable=SC1090,SC1091
if [ -f "$_wl_dplib" ] && . "$_wl_dplib" 2>/dev/null && command -v dod_read_files >/dev/null 2>&1; then
  # DOD_FILE names where NEW captures go (the "expected" path in the absent-message); the READ is
  # over BOTH sources — repo-key store + this toplevel's legacy file — summed, lossless.
  DOD_FILE="$(dod_path_for "$PWD" write)"
  _WL_DOD_SOURCES="$(dod_read_files "$PWD")"
else
  DOD_FILE="${WRAP_DOD_FILE:-}"
  if [ -z "$DOD_FILE" ]; then
    DOD_DIR="${WRAP_DOD_DIR:-$HOME/.claude/autonomy/dod}"
    TOP="$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")"
    DHASH="$(printf '%s' "$TOP" | shasum 2>/dev/null | cut -c1-16)"
    DOD_FILE="$DOD_DIR/${DHASH:-unknown}.md"
  fi
  _WL_DOD_SOURCES=""; [ -f "$DOD_FILE" ] && _WL_DOD_SOURCES="$DOD_FILE"
fi
DOD="absent"; REMAINDER=0
while IFS= read -r _wl_df; do
  [ -n "$_wl_df" ] && [ -f "$_wl_df" ] || continue
  DOD="present"
  # LINEAGE-FILTERED (row 4de3d0f9c0e1). The repo key is shared by every worktree of the repo, so
  # an unfiltered count summed a CONCURRENT wave's unchecked boxes into this wave's REMAINDER and
  # red-runged a close over items belonging to someone else. dod_filter_for keeps this wave's
  # blocks and its recorded predecessors', and keeps unattributable ones — so the count can only
  # ever fail toward "too many", never toward hiding an item this wave actually owns.
  if command -v dod_filter_for >/dev/null 2>&1; then
    _wl_r="$(dod_filter_for "$PWD" "$_wl_df" \
             | grep -cE '^[[:space:]]*[-*][[:space:]]+\[[[:space:]]\]' 2>/dev/null || echo 0)"
  else
    _wl_r="$(grep -cE '^[[:space:]]*[-*][[:space:]]+\[[[:space:]]\]' "$_wl_df" 2>/dev/null || echo 0)"
  fi
  case "$_wl_r" in ''|*[!0-9]*) _wl_r=0 ;; esac
  REMAINDER=$((REMAINDER + _wl_r))
done <<WLDOD
$_WL_DOD_SOURCES
WLDOD

# ── Operator-only steps THIS SESSION filed (the 👤 rung) ──
# Session id, in order: --session > $WRAP_SESSION_ID > $CLAUDE_SESSION_ID > unresolvable ("").
SID="$SESSION_FLAG"
SID_SRC="flag"
[ -n "$SID" ] || { SID="${WRAP_SESSION_ID:-}"; SID_SRC="WRAP_SESSION_ID"; }
[ -n "$SID" ] || { SID="${CLAUDE_SESSION_ID:-}"; SID_SRC="CLAUDE_SESSION_ID"; }
[ -n "$SID" ] || SID_SRC=""

# ── ◎ GOAL LIVENESS — is the armed /goal being EVALUATED? (E5; §9 B5) ───────────────────────────
# REPORTED, NEVER A RUNG. See the header's § GOAL for why, what each field means, and the fail
# directions. Everything below is mechanism.
#
# Transcript: the seven Stop-hook callers export $WRAP_TRANSCRIPT (they already do — it is the
# memo key), so the hot path costs one grep + one jq over a file goal-inert-watch.sh already
# greps at the same Stop, and it is memoized per event like every other field. The PULL path
# (/wrap, CLI) passes nothing, so it resolves the transcript from a session id — but ONLY there:
# a `find` across four account roots must never land on the Stop path.
GOAL_SRC="none"; GOAL_EVALS=0; GOAL_LAST="none"; GOAL_LAST_T="-"; GOAL_AGE_MIN=0
GOAL_COND=""; GOAL_LINE=""; GOAL_TP=""

# HH:MM local for an epoch, or "" — the same BSD-then-GNU ladder (and the same reason) as
# _wl_stat_ms: this fleet is macOS, the suites run on both.
_wl_hhmm() {
  local e="$1" o
  case "$e" in ''|*[!0-9]*) return 1 ;; esac
  [ "$e" -gt 0 ] || return 1
  o="$(date -r "$e" +%H:%M 2>/dev/null || true)"
  [ -n "$o" ] || o="$(date -d "@$e" +%H:%M 2>/dev/null || true)"
  [ -n "$o" ] || return 1
  printf '%s' "$o"
}

# The session id that names a transcript is NOT necessarily the one that names operator steps:
# $CLAUDE_CODE_SESSION_ID is set in a tool-call shell where $CLAUDE_SESSION_ID is not (measured
# 2026-08-15). It is used HERE and nowhere else — the 👤/⛔ rungs keep their own ladder, because a
# wrong id there attributes a SIBLING's operator steps to you (commands/wrap.md states that rule),
# while here a wrong id can only name a transcript that does not exist ⇒ GOAL_SRC=none.
_wl_find_transcript() {
  local sid="$1" r f
  [ -n "$sid" ] || return 1
  for r in ${WRAP_PROJECT_ROOTS:-$HOME/.claude/projects $HOME/.claude-secondary/projects \
                                 $HOME/.claude-tertiary/projects $HOME/.claude-quaternary/projects}; do
    [ -d "$r" ] || continue
    f="$(find "$r" -maxdepth 2 -name "$sid.jsonl" 2>/dev/null | head -1)"
    [ -n "$f" ] && { printf '%s' "$f"; return 0; }
  done
  return 1
}

compute_goal_liveness() {
  local lib tsv state evals last epoch cond now age hhmm
  GOAL_TP="$GOAL_TRANSCRIPT"
  if [ -z "$GOAL_TP" ] && [ "$MODE" != "machine" ]; then
    GOAL_TP="$(_wl_find_transcript "${SID:-${CLAUDE_CODE_SESSION_ID:-}}" || true)"
  fi
  [ -n "$GOAL_TP" ] || { GOAL_SRC="none"; return 0; }

  # ONE arbiter for the record dictionary — hooks/lib/goal-state.sh, shared with every other
  # goal-reading surface. Re-implementing the sentinel/met/failed table here is how two readers
  # of the same records start disagreeing (MEMORY.md make-the-actuator-the-arbiter).
  lib="$(dirname "$0")/../hooks/lib/goal-state.sh"
  [ -f "$lib" ] || lib="$HOME/.claude/hooks/lib/goal-state.sh"
  [ -f "$lib" ] || { GOAL_SRC="error"; return 0; }
  # shellcheck source=../hooks/lib/goal-state.sh
  # shellcheck disable=SC1090,SC1091
  . "$lib" 2>/dev/null || { GOAL_SRC="error"; return 0; }
  command -v goal_liveness >/dev/null 2>&1 || { GOAL_SRC="error"; return 0; }

  # An unreadable transcript is `error`, never `absent` — absent is the POSITIVE finding "this
  # session never armed a goal", and a read that never happened must not launder into it.
  # Bounded like every other store read on this path — and `timeout` takes a COMMAND, not a shell
  # function, so the read runs in a child that sources the lib itself. The single quotes are the
  # point: $1/$2 are that child's positional parameters (the lib path and the transcript), passed
  # as arguments so no value is ever re-parsed as script text.
  # shellcheck disable=SC2016
  tsv="$(_bounded "${WRAP_GOAL_TIMEOUT_S:-5}" bash -c '. "$1"; goal_liveness "$2"' _ "$lib" "$GOAL_TP" 2>/dev/null)" \
    || { GOAL_SRC="error"; return 0; }
  IFS=$'\t' read -r state evals last epoch cond <<< "$tsv"
  case "${evals:-}" in ''|*[!0-9]*) evals=0 ;; esac
  case "${epoch:-}" in ''|*[!0-9]*) epoch=0 ;; esac
  GOAL_SRC="${state:-error}"; GOAL_EVALS="$evals"; GOAL_LAST="${last:-none}"; GOAL_COND="$cond"

  hhmm="$(_wl_hhmm "$epoch" || true)"; [ -n "$hhmm" ] && GOAL_LAST_T="$hhmm"
  now="$(date +%s 2>/dev/null || echo 0)"; case "$now" in ''|*[!0-9]*) now=0 ;; esac
  if [ "$epoch" -gt 0 ] && [ "$now" -gt "$epoch" ]; then age=$(((now - epoch) / 60)); else age=0; fi
  GOAL_AGE_MIN="$age"

  # THE LINE — emitted for a LIVE goal only. A met/cleared/failed goal keeps its FIELDS (that is
  # what makes the pole measurable after the fact) but spends no line: a "goal met" note repeated
  # at every close for the rest of the session is an alarm that always fires, and carries exactly
  # as many bits as one that cannot (MEMORY.md alarm-polarity).
  [ "$GOAL_SRC" = "live" ] || return 0
  local when="@${GOAL_LAST_T}"; [ "$GOAL_LAST_T" = "-" ] && when=" (time unknown)"
  if [ "$GOAL_EVALS" -eq 0 ]; then
    GOAL_LINE="◎ goal: 0 evals · armed${when} (${GOAL_AGE_MIN}m ago) — armed but NEVER judged; if background work is parked, that is what is deferring it"
  else
    GOAL_LINE="◎ goal: ${GOAL_EVALS} eval(s) · last ${GOAL_LAST}${when} (${GOAL_AGE_MIN}m ago)"
  fi
}

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

# ── ⛔ — open class-C decisions THIS SESSION filed (see the header) ──
# cc-decide resolution mirrors _resolve_backlog_bin exactly: env seam first (test stub), then the
# sibling search order. Same shape on purpose — two sensors reading two operator stores through two
# different resolution models is how one of them silently stops resolving.
_resolve_decide_bin() {
  if [ -n "${CC_DECIDE_BIN:-}" ]; then printf '%s' "$CC_DECIDE_BIN"; return 0; fi
  local c
  for c in "$(dirname "$0")/../bin/cc-decide" "$HOME/.claude/bin/cc-decide" \
           "$(command -v cc-decide 2>/dev/null || true)"; do
    [ -n "$c" ] && [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

# BLOCKED = open class-C decision packets whose .session_sid == $SID. ANY failure (no binary, no jq,
# non-zero exit, timeout, unparseable json) ⇒ BLOCKED=0 + BLOCKED_SRC=error. Fail-OPEN: a decision
# store we cannot read must leave the rung EXACTLY where it was, never invent the top rung.
# The open/class predicate is cc-decide's (`list --open --class C --json`), not ours — this asks the
# ONE question the packet cannot answer for itself: is it MINE?
BLOCKED=0; BLOCKED_SRC="skip"; BLOCKED_WHAT=""
count_blocking_decisions() {
  if [ -z "$SID" ]; then BLOCKED=0; BLOCKED_SRC="none"; return 0; fi
  local bin json line n what
  bin="$(_resolve_decide_bin)" || { BLOCKED=0; BLOCKED_SRC="error"; return 0; }
  command -v jq >/dev/null 2>&1 || { BLOCKED=0; BLOCKED_SRC="error"; return 0; }
  json="$(_bounded "${WRAP_DECIDE_TIMEOUT_S:-5}" "$bin" list --open --class C --json 2>/dev/null)" \
    || { BLOCKED=0; BLOCKED_SRC="error"; return 0; }
  # ONE jq: the count AND (when there is exactly one) the prose the readout names it by. A second
  # invocation to fetch what_plain would double this rung's cost at every close for one string.
  # Count FIRST, free text LAST — nothing an operator typed into a decision can shift the field the
  # rung branches on (docs/research/TSV_FIELD_COLLAPSE_2026-07-25.md), and the gsub keeps a prose
  # newline from turning the one-line readout into two.
  line="$(printf '%s' "$json" | jq -r --arg sid "$SID" '
      [ .[] | select((.session_sid // "") == $sid) ] as $mine
      | [ ($mine | length | tostring),
          (if ($mine | length) == 1
           then ($mine[0].what_plain // "" | tostring | gsub("[\\t\\r\\n]"; " "))
           else "" end) ] | @tsv' 2>/dev/null)" \
    || { BLOCKED=0; BLOCKED_SRC="error"; return 0; }
  IFS=$'\t' read -r n what <<< "$line"
  case "${n:-}" in ''|*[!0-9]*) BLOCKED=0; BLOCKED_SRC="error"; return 0 ;; esac
  BLOCKED="$n"; BLOCKED_SRC="$SID_SRC"
  # BLOCKED_WHAT is set ONLY in the single-decision case — that is the only case where naming one
  # decision is the right answer; N>1 gets the command that lists them, and a stale "what" leaking
  # into that line would name one fork while claiming to describe several. A hand-written packet can
  # lack what_plain, so the one-decision line still falls back to something the operator can act on.
  if [ "$n" -eq 1 ]; then
    what="${what%.}"
    [ -n "$what" ] || what="an open class-C decision — see cc-decide list --open --class C"
    BLOCKED_WHAT="$what"
  fi
}

# ── W2 CUSTODY — dispatched work in flight (CLOSE_INTEGRITY; generator G1) ──────────────────────
# Every other term here is a function of LOCAL git state, so an originator whose work is mid-flight
# in dispatched /handoff sessions read ✅ by construction — the wave-abandonment generator (62
# content-stranded commits across 21 branches in 5 wave-day spikes; 111 of 115 worktrees with no
# live session). bin/cc-custody records the debt at fire time (notify-back armed ⇒ a return is
# owed) and the discharge at self-close; this term COUNTS the open set for THIS cwd and folds it
# into the rung: open custody on an otherwise-✅ tree is 🔧 — in-flight dispatched work IS a loose
# end, and the ✅ certificate must not render over it. Awaiting ARMED is the legitimate non-close
# state (session-continue's wake floor enforces the armed half); "safe to close" is not.
# CUSTODY_SRC: cwd (counted; the v1 key — a shared cwd shares the view, per-session worktrees make
# it exact) · none (no binary — most repos/machines; not counted) · error (unreadable store) ·
# skip (not computed — a worse rung already governs). Fail-OPEN like YOURS/BLOCKED: an unreadable
# custody store never manufactures a rung.
CUSTODY_OPEN=0; CUSTODY_SRC="skip"
count_open_custody() {
  local bin n
  if [ -n "${CC_CUSTODY_BIN:-}" ]; then bin="$CC_CUSTODY_BIN"
  else
    for bin in "$(dirname "$0")/../bin/cc-custody" "$HOME/.claude/bin/cc-custody" \
               "$(command -v cc-custody 2>/dev/null || true)"; do
      [ -n "$bin" ] && [ -x "$bin" ] && break; bin=""
    done
  fi
  [ -n "$bin" ] && [ -x "$bin" ] || { CUSTODY_OPEN=0; CUSTODY_SRC="none"; return 0; }
  n="$(_bounded "${WRAP_CUSTODY_TIMEOUT_S:-5}" "$bin" count --open --cwd "$PWD" 2>/dev/null)" \
    || { CUSTODY_OPEN=0; CUSTODY_SRC="error"; return 0; }
  case "$n" in ''|*[!0-9]*) CUSTODY_OPEN=0; CUSTODY_SRC="error"; return 0 ;; esac
  CUSTODY_OPEN="$n"; CUSTODY_SRC="cwd"
}

# ── LIVE LAYER — the ENFORCING store, one edge past trunk (the 🚀 rung; see the header) ──
LIVE_REPO="${WRAP_LIVE_REPO:-$HOME/Development/claude-infrastructure}"
LIVE_BUDGET_COMMITS="${WRAP_LIVE_BUDGET_COMMITS:-25}"
# 360 MINUTES = CC_DEPLOY_MAX_LAG_HOURS (2026-08-26, recycle #235). This was 60, calibrated for the
# clock this arm used to read — THIS session's HEAD, where "my landing is an hour old and still not
# live" is reasonable impatience about a session's own work. compute_live_layer now reads the age of
# the commit the LIVE LAYER IS ON, which is the quantity deploy-live.sh budgets on, and on that
# quantity the sibling's own calibrated value is 6h. The two moved together on purpose: re-pointing
# the arm while leaving 60 would fire 🚀 at every close on a lane that is legitimately mid-converge
# (the alarm-polarity bound the header block opens with), and re-calibrating without re-pointing
# would only make a blind arm blinder.
#
# THEY AGREE ON THE QUANTITY AND THE NOMINAL VALUE, NOT ON THE RESOLUTION — and the difference is up
# to an hour, so it is stated rather than implied (the first commit of this fix said "agree on both
# arms and both values", which reads as "they trip together" and they do not). deploy-live.sh:1452
# computes `LAG_HOURS=$(( (_now - _head_ts) / 3600 ))` — INTEGER hours — and trips on `-gt 6`, so its
# effective threshold is 7h. This arm compares SECONDS against 360*60, so its threshold is 6h exactly.
# There is therefore a one-hour window, age_s in (21600, 25200], where this ledger says PAST and the
# converger says inside. MEASURED IN IT, both readings at 2026-08-26T06:22:30Z with the live commit
# 23,753 s old: this ledger rendered "🚀 … past its converge budget" while deploy-live --dry-run
# printed "lag 11 commit(s) / 6h, inside the degrade budget (25 / 6h)".
#
# THAT DIRECTION IS THE CORRECT ONE and it is why the resolution is not matched. These two are not
# duplicate auditors: this one REPORTS to a closing session that the machine is not running its work
# yet, and that one DECIDES when to force a degraded deploy. A reporter that goes loud slightly
# before the actuator acts costs a true sentence an hour early; a reporter that stayed silent while
# the actuator degraded would be the bug this whole fix is about.
LIVE_BUDGET_MIN="${WRAP_LIVE_BUDGET_MIN:-360}"
# A budget that is not a number is a budget nobody can reason about — and `[ 3 -gt "" ]` is a hard
# error thrown from inside a Stop hook. Fall back to the default (deploy-live.sh:110-111 does the
# same for the same reason), never to "unbounded".
case "$LIVE_BUDGET_COMMITS" in ''|*[!0-9]*) LIVE_BUDGET_COMMITS=25 ;; esac
case "$LIVE_BUDGET_MIN"     in ''|*[!0-9]*) LIVE_BUDGET_MIN=360 ;; esac
MIG_DIR="${CC_MIGRATIONS_STATE:-$HOME/.claude/autonomy/migrations}/failed"

# LIVE=1 iff the live layer is VERIFIED at/above HEAD. LIVE_SRC carries why: ok · behind · n-a
# (positively inapplicable) · unknown (could not read) · skip (not computed — a worse rung governs).
LIVE=0; LIVE_SRC="skip"; LIVE_SHA=""; LIVE_LAG=0; MIG_FAILED=0; LIVE_BREACH=0
# LIVE_AGE = age in SECONDS of the commit the live layer is ON — the quantity the TIME budget arm
# compares. `?` on the same law as LIVE_LAG / LIVE_ADDS / LIVE_DIVERGED: the read was attempted and
# did not answer, which is NOT the same as a fresh layer (2026-08-26, recycle #236). It matters more
# here than for the siblings, because this sensor's failure value USED to be 0 — the freshest reading
# expressible, and therefore maximally CLEARING. An unresolvable sensor may not breach; the half this
# field adds is that it may not CLEAR either, so no renderer can say the time budget was applied.
LIVE_AGE=0
# LIVE_BREACH_WHY = WHICH rung of the ladder below decided: migration · diverged · adds · commits ·
# time. Empty when nothing breached. The ladder always knew; every renderer discarded it, so a TIME
# breach was reported in COMMIT units ("1 commit(s) behind and past its converge budget" against a
# budget of 25) — a sentence that contradicts itself and contradicts the sibling actuator's banner
# over the same number. Carried out of the ladder rather than re-derived by each renderer, so the
# reason a reader is given cannot drift from the reason the rung was computed on.
LIVE_BREACH_WHY=""
# LIVE_ADDS = paths HEAD carries that the live layer's tree does not — the inert-new-file count.
# `?` is its own state: the live sha could not be read HERE, so the question was asked and not
# answered. 0 alongside LIVE_SRC=skip/n-a/unknown means "not counted", which those already say.
LIVE_ADDS=0
# LIVE_DIVERGED = commits the LIVE layer's HEAD carries that its trunk does not — the count that
# says the converger is BLOCKED rather than merely behind. Same `?` law as LIVE_ADDS: the question
# was asked and not answered, which is not the same as zero.
#
# WHY IT IS A SEPARATE NUMBER FROM LIVE_LAG, AND WHY NO BUDGET MAY COVER IT (2026-08-25, recycle
# #230). LIVE_LAG is `rev-list --count HEAD..TRUNK` — a ONE-DIRECTIONAL distance. It is blind to the
# ahead side by construction, and the ahead side is precisely what stops the converger: deploy-live
# advances with `merge --ff-only "$TARGET"` (scripts/deploy-live.sh:1969), which requires live HEAD
# to be an ancestor of the target. deploy-live already classifies this state in detail — its case B
# at :1808 — and its own comment records that it "FROZE THE LIVE LAYER FOR 29 DRAIN RECYCLES".
#
# MEASURED by execution against an isolated mktemp clone, one variable moved (the fixture HEAD's own
# commit), everything else — fixture, trunk ref, origin URL, caller — held constant:
#     behind 4 / ahead 0  → LIVE_SRC=behind LIVE_LAG=4  "converging (4 behind; within the budget)"
#     behind 4 / ahead 1  → LIVE_SRC=behind LIVE_LAG=4  "converging (4 behind; within the budget)"
# BYTE-IDENTICAL readouts, while `merge-base --is-ancestor HEAD TRUNK` answered rc 0 for the first
# and rc 1 for the second. A POS control at trunk spoke differently (ok / lag 0), so the table
# discriminates. The real box was in the second state at that session's open — the shared checkout
# sat on two commits of its own — and this ledger rendered `✅ … converging … within the converge
# budget` over it. That claim is FALSE there: a converge BUDGET is a claim about TIME, and time does
# not cure a divergence. Only landing or dropping the ahead-side commits does. Hence it breaches at
# 1, exactly as an added file does, and for the same reason: no amount of waiting is the remedy.
LIVE_DIVERGED=0

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

# Sets LIVE / LIVE_SRC / LIVE_SHA / LIVE_LAG / LIVE_DIVERGED / MIG_FAILED / LIVE_BREACH. Called ONLY on the
# ✅-eligible path with a resolved trunk (see the rung block) — a worse rung cannot be changed by it.
compute_live_layer() {
  local my_origin live_origin sha lag lag_rc now ct ct_rc age_s _adds _arc _ahead _hrc

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
  #
  # CAPTURE THE BOUND'S OWN rc (2026-08-21, backlog 4fe8d531ce68's sibling read). This was
  # `|| echo 0`, which swallowed it: a timed-out or otherwise failed read produced lag=0 — inside
  # every budget — so an UNRESOLVABLE sensor rendered `✅ SAFE TO CLOSE` over a live layer it had
  # never actually measured. That is the exact inverse of this function's law two branches up.
  # `?`, not `unknown`-and-return: returning here would ALSO skip the added-file read below, and an
  # ADD breaches at lag 1 with no budget — so a transient failure on THIS read would have silenced
  # a true 🚀 that the adds read could still have found. `?` is not a number, so the commit-budget
  # arm below skips it (it is guarded), while the TIME budget and the added-file arm still decide.
  # It reaches the two out-of-repo consumers safely: completion-assert.sh and operator-readout.sh
  # both normalise a non-numeric LIVE_LAG before use.
  lag="$(_bounded "${WRAP_LIVE_TIMEOUT_S:-5}" git -C "$LIVE_REPO" rev-list --count "HEAD..$TRUNK" 2>/dev/null)"
  lag_rc=$?
  if [ "$lag_rc" -ne 0 ]; then
    lag="?"
  else
    case "$lag" in ''|*[!0-9]*) lag=0 ;; esac
  fi
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
    # ── DIVERGED: is the converger BLOCKED, or merely behind? (see LIVE_DIVERGED's header note) ──
    # The exact complement of the lag read above — same repo, same trunk ref, same bound, range
    # REVERSED — so the two numbers together answer "behind, ahead, or both" with no third fork and
    # no second model of the trunk. Deliberately NOT `merge-base --is-ancestor`: that answers yes/no,
    # and a count is what lets a reader tell one stray commit from a checkout someone has been
    # working in for a week. Read here rather than beside the ancestry test above because this is the
    # only branch where it can change a verdict — every other LIVE_SRC keeps its exact prior output,
    # which is what preserves the no-op guarantee for repos that are not the live layer's source.
    #
    # `?` on a failed bound, never 0 — a swallowed failure here is indistinguishable from a clean
    # read of "no divergence", which is the one state that gets no budget. Same scar as LIVE_ADDS
    # and LIVE_LAG (backlog 4fe8d531ce68), and the same resolution: an unresolvable sensor may not
    # breach, and it may not clear either, so it drops out and leaves the other arms deciding.
    _ahead="$(_bounded "${WRAP_LIVE_TIMEOUT_S:-5}" git -C "$LIVE_REPO" rev-list --count "$TRUNK..HEAD" 2>/dev/null)"
    _hrc=$?
    if [ "$_hrc" -ne 0 ]; then
      LIVE_DIVERGED="?"
    else
      case "$_ahead" in ''|*[!0-9]*) _ahead=0 ;; esac
      LIVE_DIVERGED="$_ahead"
    fi
    # ── ADDED FILES: the lag no budget may excuse (see the header). ──
    # A TREE diff, not a commit walk: --diff-filter=A between the live layer's tree and HEAD's tree
    # IS the question "which paths does HEAD have that the live layer does not", which is the
    # inertness question itself. It needs no second stat against the live worktree, and a path the
    # live layer already acquired by another route (rebase, cherry-pick, a branch that landed first)
    # is correctly NOT listed — a commit walk over the range would have counted it anyway.
    # NO PATH FILTER, deliberately. Restricting to the linked runtime dirs would raise the signal —
    # a new docs/ page is never "run" — but it is a SECOND model of the deployed surface beside
    # deploy-parity-assert.sh's, and a filter is a strictly-stronger suppressor: getting it wrong
    # SILENCES a real breach (MEMORY.md cost-gate-must-be-strictly-weaker). Erring loud is the
    # direction this rung is for, and LIVE_ADDS is emitted so a consumer can refine without a fork.
    # Run in THIS repo: HEAD is ours by construction, whereas the live repo may never have fetched
    # it (the same reason --is-ancestor is asked of the live side and not of ours). A linked worktree
    # shares the object store and a separate clone holds any sha at/below trunk, so the live sha is
    # readable here in both topologies; when it is not, say `?` and change NOTHING — an unresolvable
    # sensor never manufactures a rung, exactly as LIVE_SRC=unknown does one branch up.
    if git cat-file -e "${LIVE_SHA}^{commit}" 2>/dev/null; then
      # CAPTURE THE BOUND'S OWN rc (2026-08-21, backlog 4fe8d531ce68). This was `|| true`, which
      # swallowed it — and a swallowed failure is INDISTINGUISHABLE HERE from a clean read of zero
      # adds: `_adds` is empty either way, `grep -c .` answers 0, and 0 means "no added file", the
      # one converge lag that gets NO budget. So a timed-out sensor manufactured the ✅ the comment
      # four lines above forbids it from manufacturing. The `?` arm already existed but was
      # reachable ONLY through the cat-file miss, never through the bound.
      _adds="$(_bounded "${WRAP_LIVE_TIMEOUT_S:-5}" git diff --diff-filter=A --name-only "$LIVE_SHA" "$HEAD_SHA" 2>/dev/null)"
      _arc=$?
      if [ "$_arc" -ne 0 ]; then
        LIVE_ADDS="?"
      else
        LIVE_ADDS="$(printf '%s' "$_adds" | grep -c . 2>/dev/null || echo 0)"
        case "$LIVE_ADDS" in ''|*[!0-9]*) LIVE_ADDS=0 ;; esac
      fi
    else
      LIVE_ADDS="?"
    fi
  fi

  # A FAILED migration is the converger saying it ran and could NOT put a landed conclusion into its
  # enforcing store. Counted only INSIDE the applicability gate: the migration queue is this repo's
  # mechanism, so a session in another repo must never be convicted by it.
  MIG_FAILED="$(_count_failed_migrations "$MIG_DIR")"

  # ── the budget: whichever trips FIRST (deploy-live.sh:1444-1461) ──
  # THE CLOCK IS THE LIVE LAYER'S COMMIT, NOT THIS SESSION'S HEAD (2026-08-26, recycle #235). This
  # read was `git log -1 --format=%ct HEAD` — the age of the commit THIS session is on — while the
  # header block called the budget "measured from HEAD's commit time" AND "mirroring
  # CC_DEPLOY_MAX_LAG_COMMITS / CC_DEPLOY_MAX_LAG_HOURS in deploy-live.sh" inside ONE sentence.
  # Both clauses were accurate about their own half and they name DIFFERENT quantities:
  # deploy-live.sh:1451-1452 reads %ct of the commit the LIVE LAYER IS ON, and its own comment says
  # why — "the only clock that keeps ticking when trunk is quiet". Ours reset every time trunk moved.
  #
  # IT COULD ONLY FAIL IN ONE DIRECTION, AND IT IS THE DIRECTION THAT MATTERS. Wherever this arm
  # decides at all, LIVE_SHA is an ancestor of HEAD — divergence breaches two branches up — so its
  # committer date is the older of the two in any history git's own commands produce (rebase and
  # cherry-pick both restamp). The session-HEAD arm was therefore strictly WEAKER than the one it was
  # named after, and its blind region is exactly an ACTIVE session: every commit resets the clock to
  # zero, so the more a session lands into the undeployed backlog, the FURTHER its close sits from a
  # budget whose whole job is to notice the live layer standing still. Measured on this box at
  # 2026-08-26T05:43:03Z: the live layer had been pinned on a74e844377f8 for 5h56m across five
  # consecutive drain links, lag climbing 2→4→6→8→10, and each link's close read its own HEAD at 29m
  # and rendered "live layer converging (10 commit(s) behind; within the converge budget)".
  #
  # THE DEFAULT MOVED WITH THE CLOCK AND MAY NOT MOVE SEPARATELY (see LIVE_BUDGET_MIN). %ct, not
  # %at, is still the right date on either clock: an old patch re-committed today has just entered
  # the pipeline and deserves a fresh budget, where its author date would start it already expired.
  #
  # Read from the LIVE repo: its own HEAD is resolvable there by construction, the rev-parse above
  # having succeeded, whereas THIS repo may never have fetched it — the same asymmetry that puts the
  # --is-ancestor question on the live side and the added-file diff on ours. Bounded like every other
  # live-side read, and a failed read leaves ct=0 ⇒ age 0 ⇒ no time trip: an unresolvable sensor may
  # not breach, the same law as LIVE_LAG=? and LIVE_ADDS=?. `date +%s` failing lands in the same arm.
  #
  # AND THE READ IS `?` WHEN IT DOES NOT ANSWER (2026-08-26, recycle #236). Leaving ct=0 satisfied
  # "may not breach" and violated its other half: age 0 is the FRESHEST value this arm can hold, so a
  # dead clock rendered as a live layer deployed one second ago, and the readout went on to say
  # "inside the time budget" — a claim about a comparison that never happened, which is the exact
  # defect the LIVE_LAG=? arm two branches up was built to stop.
  #
  # IT MATTERS BECAUSE THE TWO FAILURES ARE CORRELATED. Before this arm was re-pointed it read THIS
  # repo's HEAD and needed no live read at all, which is what made the `?` guard's old note true.
  # Now both are `_bounded … git -C "$LIVE_REPO"` — same repo, same timeout — so the condition that
  # produces LIVE_LAG=? in the field (a live repo that is slow, locked or on a stalled mount) takes
  # the clock with it. The surviving independent sensor on that path is the added-file read, which
  # runs in OUR repo; the tests pin both the correlated case and the clock-alone case, one variable
  # apart, because a `?` proven only by a broken box proves nothing about either.
  now="$(date +%s 2>/dev/null || echo 0)"
  ct="$(_bounded "${WRAP_LIVE_TIMEOUT_S:-5}" git -C "$LIVE_REPO" log -1 --format=%ct "$LIVE_SHA" 2>/dev/null)"
  ct_rc=$?
  case "$now" in ''|*[!0-9]*) now=0 ;; esac
  if [ "$ct_rc" -ne 0 ]; then ct=0; fi
  case "$ct"  in ''|*[!0-9]*) ct=0 ;; esac
  age_s=0
  if [ "$now" -gt 0 ] && [ "$ct" -gt 0 ]; then
    # Both clocks answered ⇒ an age exists, and a commit dated in the FUTURE (a skewed committer
    # date, which git accepts) clamps to 0 rather than going `?`: that read succeeded, and 0 is the
    # true answer to "how long has it been sitting there". `?` is reserved for a read that did not
    # happen — collapsing the two would put a measured state back under the unmeasured label.
    if [ "$now" -gt "$ct" ]; then age_s=$((now - ct)); fi
    LIVE_AGE="$age_s"
  else
    LIVE_AGE="?"
  fi

  if [ "$MIG_FAILED" -gt 0 ]; then
    LIVE_BREACH=1; LIVE_BREACH_WHY="migration"
  elif [ "$LIVE_SRC" = "behind" ]; then
    # A DIVERGENCE gets NO budget either, and it is tested FIRST because it OUTRANKS the added file:
    # an absent file is cured by the next converge tick, whereas a divergence is what stops every
    # converge tick — it is the CAUSE the added-file count is a symptom of. `?` may not breach, on
    # the same law as the two arms below.
    if [ "$LIVE_DIVERGED" != "?" ] && [ "$LIVE_DIVERGED" -gt 0 ]; then
      LIVE_BREACH=1; LIVE_BREACH_WHY="diverged"
    # An ADD gets NO budget (header). `?` is not a number and must never breach — it falls through
    # to the budget arms, leaving the pre-2026-08-09 verdict exactly as it was.
    elif [ "$LIVE_ADDS" != "?" ] && [ "$LIVE_ADDS" -gt 0 ]; then
      LIVE_BREACH=1; LIVE_BREACH_WHY="adds"
    # THE TWO BUDGET ARMS — whichever trips FIRST, each guarded by its own sensor's `?`.
    #
    # BOTH GUARDS EXIST FOR THE SAME REASON AND NEITHER COVERS FOR THE OTHER (2026-08-26, recycle
    # #236). The note that used to sit here said the TIME budget "is derived from HEAD's own
    # committer date and needs no live read", which was true of the arm as written on 2026-08-21 and
    # stopped being true one link before this one: the clock now reads the live repo, through the
    # same `_bounded` and the same timeout as the lag read above. So on the failure that actually
    # occurs — a live repo that is slow, locked, or on a stalled mount — BOTH arms abstain together,
    # and what still decides is the added-file read one branch up, which runs in OUR repo. Written
    # out because the older sentence read as a guarantee of independence that the code no longer has.
    #
    # Split into two tested branches rather than one `||`: the ladder is the only place that knows
    # WHICH arm decided, and every renderer below was printing the other arm's units for want of it.
    elif [ "$LIVE_LAG" != "?" ] && [ "$LIVE_LAG" -gt "$LIVE_BUDGET_COMMITS" ]; then
      LIVE_BREACH=1; LIVE_BREACH_WHY="commits"
    elif [ "$LIVE_AGE" != "?" ] && [ "$LIVE_AGE" -gt "$((LIVE_BUDGET_MIN * 60))" ]; then
      LIVE_BREACH=1; LIVE_BREACH_WHY="time"
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
# The goal term is computed BEFORE the ladder and consumed by NONE of it — it is a report, not a
# rung (§ GOAL). Unconditional like ⛔'s read, and for the opposite reason: ⛔ cannot ride the
# ✅-eligible path because it outranks everything, this one cannot because it ranks nowhere at all.
compute_goal_liveness
# ⛔ IS CHECKED FIRST AND UNCONDITIONALLY — it outranks every rung below, so unlike 👤 and 🚀 it
# cannot ride the ✅-eligible path where a worse rung has already decided the answer. That costs ONE
# bounded fork on every turn close (this is a Stop-hook path) and it is the price of a rung that
# outranks: an operator decision left open is worse than a dirty tree, and nothing else can see it.
count_blocking_decisions
if [ "$BLOCKED" -gt 0 ]; then
  RUNG="⛔"
  if [ "$BLOCKED" -eq 1 ]; then
    READOUT="⛔ Blocked — need your call: ${BLOCKED_WHAT}."
  else
    READOUT="⛔ Blocked — ${BLOCKED} decision(s) need your call: cc-decide list --open"
  fi
elif [ "$DIRTY" -eq 1 ]; then
  RUNG="🔧"; READOUT="🔧 Loose ends — ${DIRTY_N} uncommitted change(s) in the tree; continuing."
elif [ "$REMAINDER" -gt 0 ]; then
  RUNG="🔧"; READOUT="🔧 Loose ends — ${REMAINDER} frozen-DoD item(s) remain; continuing."
elif [ "$UNLANDED" -eq 1 ]; then
  RUNG="📦"
  if [ "$LANDING" -eq 1 ]; then
    READOUT="📦 Land IN FLIGHT (pid ${LANDING_PID}, ${LANDING_AGE}s) — do NOT fire a second /ship on this worktree; await its verdict."
  else
    READOUT="📦 Done, but only on a branch (${AHEAD} commit(s) unlanded) — /ship to land it (else lost)."
  fi
else
  # ✅-eligible on the git facts. ONLY here do the custody count, the operator-step count and the
  # live-layer read matter — on the 🔧/📦 paths none can change the answer, so none is ever paid
  # for (cost discipline: Stop hook, every close; each reports SRC=skip there, so "not counted"
  # stays distinguishable from "counted zero"). A missing trunk means "landed" is unproven, so
  # neither 👤 nor 🚀 — both of which ASSERT landed — is computed there, AND the no-trunk rung is
  # ranked ahead of every remaining arm (see below): the carve-out has to cover all three, not two.
  count_open_custody
  if [ "$CUSTODY_OPEN" -gt 0 ]; then
    # In-flight dispatched work outranks every remaining arm INCLUDING no-trunk: the originator's
    # own tree being clean/landed says nothing while its wave has not returned, and the ✅
    # certificate (which needs RUNG=✅) must be unreachable here mechanically, not by discipline.
    RUNG="🔧"; READOUT="🔧 Loose ends — ${CUSTODY_OPEN} dispatched session(s) have NOT returned (cc-custody list --open --cwd .); await them ARMED (cc-await-ping), then collect+land and \`cc-custody return\` — or \`cc-custody abandon <token> --why …\`."
  else
  if [ -n "$TRUNK" ]; then compute_live_layer; count_operator_steps; fi
  if [ -z "$TRUNK" ]; then
    # No trunk resolved ⇒ UNLANDED=0 is a DEFAULT, not a measurement: nothing was ever compared, so
    # every arm below that says "landed" would be asserting a fact this run never read. This rung
    # used to sit BELOW the absent-DoD arm, whose readout opens "✅ Clean & landed" — so the abstain
    # was shadowed on the branch the case actually reaches, since a repo with no trunk usually has
    # no DoD either. Measured on 8c691106: a local-only repo read "✅ Clean & landed", the same
    # false-✅-on-unproven-landing this ladder's own origin/HEAD fix (7bc4b4e5) was written to kill.
    # The 👤/🚀 carve-out above already states the rule; this is the third arm it has to reach.
    # The sentence deliberately carries no form of the word this rung refuses to assert — the test
    # greps for it, and the first draft failed its own check by saying "(not 'landed')".
    RUNG="🔧"; READOUT="🔧 Loose ends — no upstream trunk resolved, so landing is UNPROVEN; continuing."
  elif [ "$LIVE_BREACH" -eq 1 ]; then
    # 🚀 outranks 👤: "the machine is not running this yet" is a fact about the work itself, where an
    # operator step is a fact about someone's queue.
    RUNG="🚀"
    # Three CAUSES, three sentences. The added-file cause needs its own or the line asserts
    # "past its converge budget" over a lag that is comfortably INSIDE it — a false statement, and
    # the operator's next move differs from a merely-stale layer: the file is missing, not old.
    if [ "$MIG_FAILED" -gt 0 ]; then
      READOUT="🚀 Landed but NOT live — ${MIG_FAILED} migration(s) could not reach the enforcing store; the machine is not running this yet."
    elif [ "$LIVE_DIVERGED" != "?" ] && [ "$LIVE_DIVERGED" -gt 0 ]; then
      # NOT "unlanded work": deploy-live's own classifier (:1808) splits this into B1, where every
      # diverging commit is already on trunk BY CONTENT because a rebased land rewrote the object,
      # and B2, where one is genuinely un-landed — and it is fail-closed because the two are one typo
      # apart in consequence. This sentence must be TRUE of both, so it states the mechanism (ff-only
      # cannot advance) and points at the converger, rather than guessing which of the two holds.
      READOUT="🚀 Landed but NOT live — the live layer carries ${LIVE_DIVERGED} commit(s) trunk does not, so \`merge --ff-only\` cannot advance it and NO converge budget applies; run scripts/deploy-live.sh, which names which of them are already on trunk by content."
    elif [ "$LIVE_ADDS" != "?" ] && [ "$LIVE_ADDS" -gt 0 ]; then
      READOUT="🚀 Landed but NOT live — ${LIVE_ADDS} NEW file(s) are absent from the live layer, so every consumer guard on them silently skips; no budget covers an added file."
    elif [ "$LIVE_BREACH_WHY" = "time" ]; then
      # NAME THE ARM (2026-08-26, recycle #236). This sentence used to be the COMMIT sentence for
      # both arms, so a TIME breach read "the live layer is 1 commit(s) behind and past its converge
      # budget" against a commit budget of 25 — self-contradicting arithmetic, and it contradicted
      # deploy-live's own banner over the identical lag ("lag 11 commit(s) / 6h, inside the degrade
      # budget (25 / 6h)", 2026-08-26T06:22:30Z, while this line said PAST). The two are not in
      # conflict — different arms, and the hours arm is integer-truncated so they disagree for up to
      # an hour by design — but nothing in the sentence said which arm applied, so the reader had no
      # way to tell a real disagreement from a rendering artefact. The lag is kept in the line
      # because it is still what the converger will move; it is no longer the reason.
      READOUT="🚀 Landed but NOT live — the live layer is ${LIVE_LAG} commit(s) behind and past its converge budget (the TIME arm: the commit it sits on is ${LIVE_AGE}s old, budget ${LIVE_BUDGET_MIN}m); the machine is not running this yet."
    else
      READOUT="🚀 Landed but NOT live — the live layer is ${LIVE_LAG} commit(s) behind and past its converge budget (the COMMIT arm: ${LIVE_LAG} > ${LIVE_BUDGET_COMMITS}); the machine is not running this yet."
    fi
  elif [ "$YOURS" -gt 0 ]; then
    # 👤 outranks the absent-DoD note: an unrun operator step is a fact, an unverifiable scope is not.
    RUNG="👤"; READOUT="👤 My side is done & landed — ${YOURS} step(s) need you; see the OPERATOR block."
  elif [ "$DOD" = "absent" ]; then
    # ✅-eligible git state, but no durable DoD to confirm the scope was met → say so, never silent ✅.
    RUNG="✅"; READOUT="✅ Clean & landed — but NO durable DoD to confirm scope (completeness unverified; frozen a DoD via ~/.claude/autonomy/dod)."
  elif [ "$LIVE_SRC" = "behind" ]; then
    # Behind but INSIDE the converge budget — the normal, expected state for the first minutes after
    # a land. Not a rung (it would fire at every close), but not silent either: the one line says
    # the conclusion is in flight. It ranks last because an absent DoD is the less-verified fact and
    # wins the single line; this one still reaches every consumer via LIVE_SRC/LIVE_LAG below.
    # "within the converge budget" is a CLAIM ABOUT A MEASUREMENT, so it may only be said when the
    # measurement was made. On `?` the commit budget abstained and the TIME budget is what cleared
    # this close — say that, rather than asserting a bound on a lag nothing read (2026-08-21).
    if [ "$LIVE_LAG" = "?" ] && [ "$LIVE_AGE" = "?" ]; then
      # BOTH live-side sensors abstained (2026-08-26, recycle #236) — the correlated failure, since
      # they are the same repo through the same bound. The rung is unchanged, because an unresolvable
      # sensor may not breach; the SENTENCE is what changes, because it may not clear either. The
      # older line credited "inside the time budget" on this path, which was written when that arm
      # read our own HEAD and could not fail with the lag. Only the added-file read is left, and it
      # is named as the only thing that actually answered.
      RUNG="✅"; READOUT="✅ Complete & landed — live layer state UNREADABLE (commit lag and live-commit age both unread; no added file, so no budget was applied and nothing breached)."
    elif [ "$LIVE_LAG" = "?" ]; then
      RUNG="✅"; READOUT="✅ Complete & landed — live layer converging (commit lag UNREADABLE; no added file and inside the time budget)."
    elif [ "$LIVE_AGE" = "?" ]; then
      # The mirror image, and it gets its own line for the same reason the one above does: naming
      # the arm that DID clear is the only way the reader can tell an applied budget from an
      # abstained one. "the converge budget" would assert both.
      RUNG="✅"; READOUT="✅ Complete & landed — live layer converging (${LIVE_LAG} commit(s) behind; within the COMMIT budget — the live-commit clock was UNREADABLE, so the time budget was not applied)."
    else
      RUNG="✅"; READOUT="✅ Complete & landed — live layer converging (${LIVE_LAG} commit(s) behind; within the converge budget)."
    fi
  fi
  fi   # closes the CUSTODY_OPEN branch (its 🔧 arm above short-circuits this whole chain)
fi

emit_machine() {
  printf 'RUNG=%s\n' "$RUNG"
  printf 'READOUT=%s\n' "$READOUT"
  printf 'DIRTY=%s\n' "$DIRTY"
  printf 'DIRTY_N=%s\n' "$DIRTY_N"
  printf 'AHEAD=%s\n' "$AHEAD"
  printf 'CHERRY=%s\n' "$CHERRY"
  printf 'UNLANDED=%s\n' "$UNLANDED"
  printf 'LANDING=%s\n' "$LANDING"
  printf 'LANDING_PID=%s\n' "$LANDING_PID"
  printf 'LIVE=%s\n' "$LIVE"
  printf 'LIVE_SRC=%s\n' "$LIVE_SRC"
  printf 'LIVE_SHA=%s\n' "$LIVE_SHA"
  printf 'LIVE_LAG=%s\n' "$LIVE_LAG"
  printf 'LIVE_ADDS=%s\n' "$LIVE_ADDS"
  printf 'LIVE_DIVERGED=%s\n' "$LIVE_DIVERGED"
  printf 'LIVE_AGE=%s\n' "$LIVE_AGE"
  printf 'LIVE_BREACH_WHY=%s\n' "$LIVE_BREACH_WHY"
  printf 'MIG_FAILED=%s\n' "$MIG_FAILED"
  printf 'GATE=%s\n' "$GATE"
  printf 'DOD=%s\n' "$DOD"
  printf 'DOD_FILE=%s\n' "$DOD_FILE"
  printf 'REMAINDER=%s\n' "$REMAINDER"
  printf 'CUSTODY_OPEN=%s\n' "$CUSTODY_OPEN"
  printf 'CUSTODY_SRC=%s\n' "$CUSTODY_SRC"
  printf 'YOURS=%s\n' "$YOURS"
  printf 'YOURS_SRC=%s\n' "$YOURS_SRC"
  printf 'BLOCKED=%s\n' "$BLOCKED"
  printf 'BLOCKED_SRC=%s\n' "$BLOCKED_SRC"
  printf 'GOAL_SRC=%s\n' "$GOAL_SRC"
  printf 'GOAL_EVALS=%s\n' "$GOAL_EVALS"
  printf 'GOAL_LAST=%s\n' "$GOAL_LAST"
  printf 'GOAL_LAST_T=%s\n' "$GOAL_LAST_T"
  printf 'GOAL_AGE_MIN=%s\n' "$GOAL_AGE_MIN"
  printf 'GOAL_LINE=%s\n' "$GOAL_LINE"
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
  # The BEHIND verdict is three-valued, not two: an added file breaches with the lag still inside
  # the budget, so "PAST budget" would be a false reason attached to a true rung.
  # `within budget (N)` asserts a COMPARISON; on an unreadable lag no comparison was made, and
  # printing the budget beside a `?` reads as though it had been (2026-08-21). Stated as the base
  # rather than appended, so the stronger causes below still overwrite it — but each of those names
  # a fact that was actually READ, so none of them inherits the phantom comparison.
  #
  # THE BUDGET IS TWO-ARMED AND THIS ROW USED TO NAME ONE OF THEM (2026-08-26, recycle #236). The
  # base clause printed the COMMIT budget's number on every non-breaching path, and "PAST budget"
  # carried no arm at all — so a TIME breach rendered as "BEHIND — 1 commit(s), PAST budget" beside a
  # commit budget of 25. Both arms are now named from LIVE_BREACH_WHY, which the ladder sets where
  # the decision is made, so this row cannot drift from the rung. `?` on either sensor drops that
  # arm's clause instead of printing a comparison nothing made — the same law the lag clause already
  # carried, now applied to the clock the time arm reads.
  local behind_why="within budget (${LIVE_BUDGET_COMMITS} commit(s) / ${LIVE_BUDGET_MIN}m)"
  if [ "$LIVE_LAG" = "?" ] && [ "$LIVE_AGE" = "?" ]; then
    behind_why="commit lag AND live-commit age both UNREADABLE — no budget applied"
  elif [ "$LIVE_LAG" = "?" ]; then
    behind_why="commit lag UNREADABLE — commit budget not applied; within the time budget (${LIVE_BUDGET_MIN}m)"
  elif [ "$LIVE_AGE" = "?" ]; then
    behind_why="live-commit age UNREADABLE — time budget not applied; within the commit budget (${LIVE_BUDGET_COMMITS})"
  fi
  if [ "$LIVE_ADDS" = "?" ]; then behind_why="${behind_why} · added-file check UNRESOLVED"
  elif [ "$LIVE_ADDS" -gt 0 ]; then behind_why="${LIVE_ADDS} NEW file(s) ABSENT — no budget covers an add"
  elif [ "$LIVE_BREACH" -eq 1 ]; then
    case "$LIVE_BREACH_WHY" in
      time)    behind_why="PAST budget — the TIME arm (live commit ${LIVE_AGE}s old > ${LIVE_BUDGET_MIN}m)" ;;
      commits) behind_why="PAST budget — the COMMIT arm (${LIVE_LAG} > ${LIVE_BUDGET_COMMITS})" ;;
      *)       behind_why="PAST budget" ;;
    esac
  fi
  local live_disp; case "$LIVE_SRC" in
    ok)      live_disp="at/above HEAD ($(printf '%s' "$LIVE_SHA" | cut -c1-8))" ;;
    behind)  live_disp="BEHIND — ${LIVE_LAG} commit(s), ${behind_why}" ;;
    n-a)     live_disp="n/a (this repo is not the live layer's source)" ;;
    unknown) live_disp="unknown (live repo unreadable — not counted)" ;;
    *)       live_disp="not counted (a worse rung governs)" ;;
  esac
  [ "$MIG_FAILED" -gt 0 ] && live_disp="${live_disp} · ${MIG_FAILED} FAILED migration(s) — conclusion never reached its enforcing store"
  printf 'Live layer:     %s\n' "$live_disp"
  local custody_disp; case "$CUSTODY_SRC" in
    cwd)   custody_disp="$( [ "$CUSTODY_OPEN" -gt 0 ] && printf '%s dispatched session(s) NOT returned — cc-custody list --open --cwd .' "$CUSTODY_OPEN" || printf 'none open for this cwd' )" ;;
    none)  custody_disp="not tracked (no cc-custody binary)" ;;
    error) custody_disp="unknown — custody store unreadable (not counted)" ;;
    *)     custody_disp="not counted (a worse rung governs)" ;;
  esac
  printf 'Dispatched:     %s\n' "$custody_disp"
  local yours_disp; case "$YOURS_SRC" in
    none)  yours_disp="unknown — session id unresolvable (not counted)" ;;
    error) yours_disp="unknown — backlog unreadable (not counted)" ;;
    skip)  yours_disp="not counted (a worse rung governs)" ;;
    *)     yours_disp="$( [ "$YOURS" -gt 0 ] && printf '%s operator-only step(s) filed this session, UNRUN — see the OPERATOR block' "$YOURS" || printf 'none filed this session' )" ;;
  esac
  printf 'Yours (operator): %s\n' "$yours_disp"
  # The top rung's own row. `skip` is unreachable here by construction (⛔ outranks everything, so
  # it is always computed) — the arm stays so an unreadable store can never render as "none open".
  local blocked_disp; case "$BLOCKED_SRC" in
    none)  blocked_disp="unknown — session id unresolvable (not counted)" ;;
    error) blocked_disp="unknown — decision store unreadable (not counted)" ;;
    skip)  blocked_disp="not counted (a worse rung governs)" ;;
    *)     if   [ "$BLOCKED" -gt 1 ]; then blocked_disp="${BLOCKED} open class-C decision(s) filed this session, UNRESOLVED — cc-decide list --open --class C"
           elif [ "$BLOCKED" -eq 1 ]; then blocked_disp="1 open class-C decision filed this session, UNRESOLVED — ${BLOCKED_WHAT}"
           else                            blocked_disp="none — no decision of mine is open"; fi ;;
  esac
  printf 'Blocked on you: %s\n' "$blocked_disp"
  # ◎ The goal row. Reported for EVERY state, unlike the ◎ line — the row is the oracle itself
  # (zero-eval vs healthy-deferral, § GOAL), and a row that vanished on the cleared/absent cases
  # would answer "is this session's goal being judged?" with silence in exactly the cases where
  # silence is indistinguishable from a broken reader.
  local goal_disp cond_disp
  cond_disp="$GOAL_COND"; [ "${#cond_disp}" -gt 60 ] && cond_disp="${cond_disp:0:57}..."
  case "$GOAL_SRC" in
    live)    if [ "$GOAL_EVALS" -eq 0 ]; then
               goal_disp="LIVE · 0 evaluations since arm@${GOAL_LAST_T} (${GOAL_AGE_MIN}m) — NEVER judged"
             else
               goal_disp="LIVE · ${GOAL_EVALS} evaluation(s) · last ${GOAL_LAST}@${GOAL_LAST_T} (${GOAL_AGE_MIN}m)"
             fi
             [ -n "$cond_disp" ] && goal_disp="${goal_disp} · \"${cond_disp}\"" ;;
    cleared) goal_disp="cleared (${GOAL_LAST}@${GOAL_LAST_T}) after ${GOAL_EVALS} evaluation(s)" ;;
    failed)  goal_disp="FAILED — the evaluator judged it impossible@${GOAL_LAST_T}; CC cleared it" ;;
    absent)  goal_disp="none armed in this session" ;;
    error)   goal_disp="unknown — transcript/lib unreadable (not counted)" ;;
    *)       goal_disp="unknown — no transcript on this path (not counted)" ;;
  esac
  printf 'Goal (◎):       %s\n' "$goal_disp"
  printf 'Rung:           %s\n' "$RUNG"
  printf 'Next:           %s\n' "$(rung_next)"
}

rung_next() {
  case "$RUNG" in
    "⛔") printf 'STOP-ASK — put the decision in line 1 and hand it back; nothing below it closes (cc-decide list --open --class C)' ;;
    "🔧") printf 'continue → finish · run-gate · commit (explicit paths)' ;;
    "📦") if [ "$LANDING" -eq 1 ]; then
            printf 'AWAIT the land already in flight (pid %s) — a second /ship on this worktree only queues behind it' "$LANDING_PID"
          else
            printf '/ship to land (verified net-positive work is drivable — not a hold)'
          fi ;;
    "🚀") printf 'bash scripts/deploy-live.sh — %s; the conclusion is landed but inert' \
            "$( if [ "$LIVE_ADDS" != "?" ] && [ "$LIVE_ADDS" -gt 0 ]; then \
                  printf '%s NEW file(s) never reached the live layer' "$LIVE_ADDS"; \
                else printf 'the converger is behind its budget'; fi )" ;;
    "👤") printf 'surface the OPERATOR block — %s step(s) are the operator'"'"'s (my side is done)' "$YOURS" ;;
    "✅") printf 'complete — nothing to do' ;;
    *)    printf 'model-state (📤) overrides — surface it' ;;
  esac
}

case "$MODE" in
  machine)
    if [ -n "$WL_KEY" ]; then
      # Build once, print once, store once. The store is best-effort and NEVER gates the answer:
      # this caller has computed a true ledger and must emit it whether or not the memo takes.
      WL_OUT="$(emit_machine)"
      _wl_cache_store "$WL_OUT"
      printf '%s\n' "$WL_OUT"
    else
      emit_machine
    fi
    ;;
  full)    emit_full ;;
  # The ◎ line ALONE, so a pull surface can print it beside the rung without the rung line growing
  # a second clause (the default readout is ONE line — tests/wrap-ledger.bats pins that, and a
  # close's line 1 is the rung, unhedged, per CLAUDE.md §Session Close). Nothing to say ⇒ NOTHING
  # printed, rc 0: a `/wrap` in a goal-less session must not gain a line of chrome.
  goal)    [ -n "$GOAL_LINE" ] && printf '%s\n' "$GOAL_LINE" ;;
  *)       printf '%s\n' "$READOUT" ;;
esac
_wl_lock_release
exit 0
