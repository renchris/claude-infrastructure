#!/usr/bin/env bash
# drain-chain-assert.sh — IS THE 24/7 DRAIN CHAIN ALIVE? (docs/plans/BACKLOG_DRAIN_24_7.md §6)
#
# ── THE DEFECT THIS CLOSES, AND IT IS THE PLAN'S OWN ROOT CAUSE ─────────────────────────────────
# BACKLOG_DRAIN_24_7 §1.2, measured: the local drain ran NINE recycles (2026-08-13T03:56Z →
# 2026-08-16T06:45Z), recycle #9's goal cleared on an effort-scoped condition, and **no recycle #10
# fired**. Nothing chained effort N's clear into effort N+1's fire, and — the part this file is
# about — *nothing noticed*. The chain stopped at 06:45Z and the only instrument that ever reported
# it was the operator, hours later, reading a "drained to zero" close that was per-effort and blind
# to its own blocked tail (§1.1). A 24/7 pipeline whose death is detected by a human is not 24/7;
# it is a pipeline plus a standing obligation to watch it.
#
# §6 states the invariant this script is:
#
#     The chain is alive ⟺ a fire-drain-recycle-N brief younger than 24h exists
#                        OR a drain session holds a live lease
#                        — checked by autonomy-sweep; a dead chain files ONE condition-keyed row
#                        (`local-drain-chain-dead`), never a duplicate storm.
#
# It was written as an invariant and implemented by nothing: `fire-drain-recycle` appeared in the
# plan and in NO script, test or plist on trunk. That is this repo's most-rediscovered defect — a
# conclusion that never reached an enforcing store — and filing it as prose inside the plan that
# diagnoses it would have been the same mistake one level up.
#
# ── THE INVARIANT ABOVE IS THE ONE THIS FILE NOW REFUSES TO IMPLEMENT (backlog d6d4b85ebd4c) ────
# "A brief younger than 24h" is THE AGE OF A FILE THE CHAIN WROTE WHEN IT LAST STARTED. A recycle
# brief is authored by the predecessor and stamped at the moment the successor is FIRED — never
# while that successor works. So a session that wedges at a PreToolUse modal ONE MINUTE after launch
# certifies its own chain alive for the next twenty-four hours, and that is not a hypothetical: the
# chain dead-stopped ~4 h at recycle #21 (pane 131 wedged on `rm -r /tmp/_ce`, backlog 7da9c4451540)
# and this detector filed NOTHING — zero `local-drain-chain-dead` rows at any status across its
# entire deployed life. Re-sampled live 2026-08-18T22:33Z, still answering
# `chain ALIVE (fresh-brief) · 417 live row(s) · newest brief 2950s old`.
#
# The caller was never the problem (autonomy-sweep § 2b-v, 300 s, condition-keyed, self-falsifying —
# this is NOT the built-and-never-called pattern). The PREDICATE was: a proxy the healthy population
# and the dead population both satisfy carries no bits (memories `liveness-proxy-cannot-be-output-
# age`, `orphanhood-is-not-a-discriminating-signal`). The magnitude was never the defect either —
# SHORTENING the 24 h window only makes a healthy long-running recycle look dead, so
# CC_DRAIN_CHAIN_MAX_AGE_S is deliberately unchanged. The AXIS is what moved:
#
#     alive ⟺ zero live rows (drained)
#           ∨ the chain fired inside the HANDOVER GRACE (nothing is knowable yet — see below)
#           ∨ somebody holds a live lease
#           ∨ the session that brief was fired into is STILL PROGRESSING
#
# A fresh brief is now NECESSARY but never SUFFICIENT: brief-fresh-and-nothing-progressing is
# precisely the wedge, and it reads `dead`.
#
# ── THE PROGRESS ORACLE, AND WHY IT IS THIS CHAIN AND NOT A STAMP ───────────────────────────────
# newest brief → its `prompt_file` row in handoffs.jsonl → `target_pane` → the cc-registry row →
# `.session_id` → `<sid>.jsonl` under any account home → a content-bearing assistant turn (the
# parity-pinned `assistant_turn_in` in hooks/lib/engagement.sh, which this file SOURCES rather than
# re-spells) AND an mtime younger than CC_DRAIN_PROGRESS_MAX_AGE_S.
#
# BOTH halves are load-bearing and they fail in opposite directions. The mtime alone would call a
# newborn transcript — system and attachment rows land before the model has done anything — a
# working session (`BIRTH IS NOT ENGAGEMENT`, handoff-fire item ff2d6609a33e). `assistant_turn_in`
# alone is the CURRENT bug one level in: the wedged pane at #21 had taken real assistant turns
# minutes before it froze, so an ever-engaged test says green forever. Recency over an
# append-per-record file is what separates them: a transcript grows on every message, so a frozen
# one is a session that is emitting nothing — the state a PreToolUse modal produces and no other
# instrument on this box reports (docs/research/cc-startup-modals-2026-08-04.md).
#
# WHY THE WINDOW IS AN HOUR AND NOT A MINUTE. The transcript is also frozen for the whole duration
# of a single long tool call — the assistant record carrying the `tool_use` is written BEFORE the
# tool runs — so this axis measures how long the session has been silent, not how hard it is
# working. The longest legitimate silence on this box is a bounded sub-job (`_bounded`, 1500 s at
# the premise pass), so 3600 s is ~2.4× the worst honest quiet. It is a magnitude and it is
# tunable; the incident it has to catch was four HOURS.
#
# ── THE BLIND WINDOW AT EVERY RECYCLE, WHICH A NAIVE PROGRESS CHECK CONVICTS ────────────────────
# Between the fire and the successor's first turn there is a window in which the registry row is
# being rewritten and the new transcript does not exist yet — nothing about the successor is
# knowable, and this is the state of a PERFECTLY HEALTHY chain at every single recycle. The lead
# that filed this row misread exactly that window once already (a 42-minute-old brief beside a
# 1-minute-old ping) and called a live chain dead. A detector that convicts there would file its
# false row at every handover, forever — the alarm-that-always-fires, which carries as many bits as
# one that never fires (memory `alarm-polarity-and-attention-budget`).
#
# So a brief younger than CC_DRAIN_HANDOVER_GRACE_S is ALIVE on the fire alone (`handover-grace`),
# and it is BOUNDED rather than open-ended: a wedged successor stops firing by definition, so its
# brief ages out of the grace and the progress arm takes the verdict back. The cost of the grace is
# at most one grace-width of detection latency against an incident measured in hours.
#
# The 42-minute case is NOT the grace's — it is the progress arm's, and both are pinned separately
# in tests/drain-chain-assert.bats: a brief past the grace beside a live transcript must read alive,
# or this fix has bought its detection with a false positive at every recycle.
#
# ── WHY IT FILES RATHER THAN PRINTS, AND WHY THE ROW IS CONDITION-KEYED ─────────────────────────
# Same reasoning as backlog-grouping-sweep.sh, whose shape this deliberately copies: a printed
# warning dies with the terminal that showed it, and the drain chain dies UNATTENDED by definition
# — at 06:45Z with nobody watching is exactly the case. `--condition local-drain-chain-dead` folds
# every later filing onto ONE row (cc-backlog's dedupe + cmd_add's update arm keeps its title
# current), so a chain that stays dead for a week is one standing row and not 2,016 of them. A
# detector for backlog inflow that mints a row per 300 s tick would be funny once and then be the
# largest single generator in the store.
#
# ── THE ROW CARRIES ITS OWN RETRACTION ─────────────────────────────────────────────────────────
# `--assert` has exactly the polarity cc-premise's falsifier contract wants: rc 1 while the chain
# is dead, rc 0 the moment a recycle fires or a worker takes a lease. So the row retires itself
# when the condition clears, with no human in the loop — the difference between an alarm with a
# consumer and an alarm with a pager.
#
# ── THE TWO ARMS THAT MADE THIS FILE STRUCTURALLY UNABLE TO SAY `dead` (2026-08-31) ─────────────
# The predicate above is right and it still never fired. Across its whole deployed life this
# detector has filed ZERO `local-drain-chain-dead` rows at any status — and it MISSED a real
# 40.5-hour death: brief #259 was written 2026-08-28T23:56:02Z and #260 not until
# 2026-08-30T16:28:25Z (145,943 s; Aug 29 fired no recycle at all). Two independent structural
# blind arms, either of which alone is sufficient to explain the silence:
#
#   (a) THE BRIEF GLOB POINTED AT A DIRECTORY THE CHAIN DOES NOT WRITE. The default was
#       `/tmp/fire-drain-recycle*.txt`; §4.1's template says /tmp, but the live chain has written
#       `$HOME/.claude/autonomy/fire-drain-recycle<N>.txt` for its whole modern life. Measured
#       2026-08-31 against the running chain: `--json` reported `brief:null, brief_age_s:null` with
#       279 briefs on disk. So `FRESH` was PERMANENTLY 0, and with it BOTH arms that can only speak
#       about a chain that has recycled at all — the handover grace and the progress oracle — were
#       unreachable. The whole predicate rewrite of 2026-08-18 was dead code on this box.
#       A SECOND HOP OF THE SAME ARM: the fire is logged to handoffs.jsonl with the POINTER it is
#       fired with (`fire-pointer-<N>.txt`, 152 bytes, "read the brief in full"), never the 300 KB
#       brief the glob matches — the chain grew that indirection when the brief outgrew a prompt.
#       So hop 1's `prompt_file == $BRIEF` join could not match either, and fixing the glob alone
#       would have converted a permanent false ALIVE into a permanent false DEAD at every tick.
#       The join is therefore on the RECYCLE NUMBER (the digit run in the basename), which is
#       spelling-independent — an enumeration of the four filename spellings seen so far would be
#       the `denylist-enumerates-spellings-not-the-class` defect one layer in.
#
#   (b) GUARD 3 — "ANY LIVE CLAIM COUNTS, WHOEVER HOLDS IT" — IS REFUTED AS WRITTEN, AND ITS OWN
#       REASONING IS WHAT REFUTES IT. It was argued below on the premise that "a Lane A cloud
#       worker draining a row is the chain doing its job as much as Lane B is". Lane A is not
#       draining: DRAIN_CIRCUIT_2026-09-01 §1.3 measures 1 of 17 dispatched items ever reaching
#       `done`, because the dispatcher claims, the worker never lands, `cc-backlog-reap` blocks
#       then unblocks, and the row is re-claimed five minutes later, forever. That oscillation
#       keeps `venue:"cloud"` leases live around the clock, so this disjunct is a CONSTANT — and a
#       disjunct that is always true makes every arm after it unreachable. That is precisely this
#       file's own stated lesson (`liveness-proxy-cannot-be-output-age`,
#       `alarm-polarity-and-attention-budget`): a proxy the healthy and the dead population both
#       satisfy carries no bits. Measured over the 40.5 h window: 24 claims, ALL of them
#       `venue:"cloud"`, and a live sample on 2026-08-31 read `alive/live-lease` on two cloud
#       leases whose holder PIDs were both already dead.
#       THE FIX IS THE NARROWEST ONE THAT RESTORES THE BITS: a `venue:"cloud"` lease no longer
#       proves THIS chain alive. It is not ignored — it is counted, reported as `cloud_leases`,
#       and NAMED in the filed row's title, because a "nothing is working them" claim that hides a
#       stratum is the `zero-claim-must-name-its-excluded-strata` defect. Every other holder still
#       counts, and a row whose venue cannot be read counts as local: the abstention still runs
#       toward ALIVE, which remains the only direction this alarm may be wrong in.
#       WHY THIS IS THE RIGHT SUBJECT: every `dead` title this file writes prescribes a LANE B
#       remedy ("restart it with the Lane B recycle-fire template in §4.1"). A detector whose only
#       remedy is Lane B's must be keyed on Lane B's liveness, or it is answering a question it
#       cannot act on.
#
# ── THE THREE FAIL-OPEN GUARDS, EACH ONE LOAD-BEARING ──────────────────────────────────────────
#   1. NO STORE / NO TOOL / UNREADABLE FOLD ⇒ alive:skipped. "I could not ask" must never render as
#      "the answer was no" (backlog-grouping-sweep.sh's own lesson). A detector that convicts on an
#      unreadable store files a row about the drain when the actual fault is jq.
#   2. ZERO LIVE ROWS ⇒ alive:drained. THIS IS THE SUCCESS STATE, not a defect: §6's own terminal
#      condition is "at true zero live rows, write the chain-complete entry". A chain with nothing
#      to drain is correctly stopped, and a detector that fired there would file its first row on
#      the day the program succeeded and then hold it open forever (memory:
#      cap-whose-population-is-empty — the same trap that left backlog-ratchet.sh red on every run
#      it had ever made, against a 100% high-water its population could not reach).
#   3. ANY LIVE CLAIM COUNTS, whoever holds it. §6 says "a drain session holds a live lease" and
#      this does not try to prove the holder is *the* drain session: `by` is a worker id, the two
#      lanes fire under different ones, and a Lane A cloud worker draining a row is the chain doing
#      its job as much as Lane B is. The question the invariant asks is "is anything draining", and
#      on an ambiguous read the alarm abstains rather than convicts.
#
# ALL THREE SURVIVE THE PREDICATE CHANGE UNTOUCHED, and they are checked BEFORE the progress arm is
# ever reached — an unreadable store still answers `skipped`, an empty pile still answers `drained`,
# and any live lease still answers `live-lease` without the successor having to be identified at all.
#
# ⚠️ THE PROGRESS ARM IS THE ONE PLACE THIS FILE IS FAIL-CLOSED, DELIBERATELY. If the brief is fresh,
# the grace has expired, no lease is held, and the successor cannot be RESOLVED at all (no
# handoffs.jsonl row for that brief, no registry row, no transcript), the verdict is `dead` with
# `why=unverifiable` — not `skipped`. That is not an oversight of guard 1's rule: guard 1 is about
# THE STORE, where "I could not ask" genuinely leaves the question open, whereas here the question
# has already been answered by the store — the pile is non-empty and no one holds it — and an
# unfindable successor is one of the ways a chain is dead rather than a reason to stop asking. The
# blindness this file existed in for its whole deployed life came from resolving exactly this state
# to alive. The `why` token names which of the three dead states was reached (`no-brief-no-lease` ·
# `stalled` · `unverifiable`) so a false row is diagnosable from the row itself rather than by
# re-deriving it (memory `claimed-outcome-vs-checked-outcome`).
#
# LEASE FRESHNESS IS `lastTs`, WHICH IS AN OVER-READ AND DELIBERATELY SO. A claimed row's lastTs is
# normally its claim record, but a later non-venue record (a `link`, say) moves it — so a stale
# claim can read fresh. That error only ever runs toward "alive", i.e. toward NOT filing, which is
# the direction an alarm may be wrong in. The precise claim clock lives in cc-backlog's reap fold
# and is not exposed by `list --json`; reproducing it here would be a second state model of the
# same store, which is how sibling auditors drift (memory: sibling-auditors-must-share-the-state-
# model). CC_BACKLOG_STALE_CLAIM_S is read from the SAME env `cc-backlog reap` reads, so the TTL
# cannot fork.
#
# Usage:
#   drain-chain-assert.sh            report the verdict; SILENT when the chain is alive
#   drain-chain-assert.sh --assert   exit 1 when the chain is dead (the falsifier / a gate)
#   drain-chain-assert.sh --file     file/update ONE condition-keyed row when dead
#   drain-chain-assert.sh --json     the verdict as one JSON object (machine consumers)
# Env:
#   CC_DRAIN_BRIEF_GLOB       a NEWLINE-separated list of globs; default = the live chain's own
#                             directory ($CLAUDE_CONFIG_DIR/autonomy) FIRST, then /tmp (§4.1's
#                             historical path, kept so an old-shaped chain is still seen). A
#                             single-line value is one glob, which is what every prior caller passed
#   CC_DRAIN_CHAIN_MAX_AGE_S  default 86400 (§6's "younger than 24h") — a CEILING on the brief, and
#                             deliberately unchanged: shortening it convicts a healthy long recycle
#   CC_DRAIN_PROGRESS_MAX_AGE_S default 3600 — how long the fired session's transcript may be silent
#   CC_DRAIN_HANDOVER_GRACE_S default 900 — the window after a fire in which nothing is knowable yet
#   CC_DRAIN_HANDOFF_LOG      default "$HOME/.claude/logs/handoffs.jsonl" — brief → target_pane
#   CC_DRAIN_PANE             skip the log lookup and name the drain pane outright
#   CC_REGISTRY_DIR · CC_ENGAGE_HOMES — hooks/lib/engagement.sh's own seams, honoured as-is
#   CC_BACKLOG_STALE_CLAIM_S  default 5400  — SHARED with `cc-backlog reap`, never re-defaulted here
#   CC_BACKLOG_BIN · CC_DRAIN_NOW (test clock)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$HERE")"
BACKLOG_BIN="${CC_BACKLOG_BIN:-$REPO/bin/cc-backlog}"
# A LIST, newline-separated, because the chain's real directory and §4.1's documented /tmp path are
# both legitimate places to find a brief and neither may shadow the other. Newlines rather than
# spaces so a home directory containing one cannot silently split a path in half. A caller passing a
# single glob (every existing one, including tests/drain-chain-assert.bats) is a one-element list.
# $HOME/.claude is listed BESIDE $CLAUDE_CONFIG_DIR rather than only as its fallback: an agent
# session runs under an isolated config dir (`.claude-tertiary` here) while autonomy-sweep runs under
# `~/.claude`, so resolving only the caller's own dir makes the answer depend on WHO ASKED — the
# detector would see the chain from the sweep and not from a session, or the reverse. Newest match
# across all globs wins, so listing a directory that does not exist costs nothing.
BRIEF_GLOB="${CC_DRAIN_BRIEF_GLOB:-$(printf '%s\n%s\n%s' \
  "${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/autonomy/fire-drain-recycle*.txt" \
  "${HOME:-}/.claude/autonomy/fire-drain-recycle*.txt" \
  "/tmp/fire-drain-recycle*.txt")}"
MAX_AGE="${CC_DRAIN_CHAIN_MAX_AGE_S:-86400}"
PROGRESS_MAX_AGE="${CC_DRAIN_PROGRESS_MAX_AGE_S:-3600}"
HANDOVER_GRACE="${CC_DRAIN_HANDOVER_GRACE_S:-900}"
HANDOFF_LOG="${CC_DRAIN_HANDOFF_LOG:-${HOME:-}/.claude/logs/handoffs.jsonl}"
REGISTRY_DIR="${CC_REGISTRY_DIR:-${HOME:-}/.claude/cc-registry}"
STALE_CLAIM="${CC_BACKLOG_STALE_CLAIM_S:-5400}"
NOW="${CC_DRAIN_NOW:-$(date +%s)}"
MODE="report"

while [ $# -gt 0 ]; do
  case "$1" in
    --assert) MODE="assert"; shift ;;
    --file)   MODE="file";   shift ;;
    --json)   MODE="json";   shift ;;
    --help|-h) sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 0 ;;
    *) printf 'drain-chain-assert: unknown arg %s\n' "$1" >&2; exit 2 ;;
  esac
done

# BSD-first mtime with a GNU fallback whose BSD attempt is CAPTURED AND VALIDATED, never let
# through — the exact shape landed in bin/cc-memory-rotate (4d7bc86d) after this idiom's naive form
# made that rotor a silent no-op on every Linux host. `stat -f` means "format" on BSD and
# "--file-system" on GNU, and GNU takes no format operand: it exits 1, so a bare `||` fallback does
# fire, but it ALSO prints a filesystem block ("File: …", "Block size: …") to STDOUT that
# `2>/dev/null` does not touch. Concatenated with the GNU answer that yields multiline junk, and
# here it would silently drop every brief — the detector would report a dead chain on a box that
# was draining fine, which is the one direction this alarm may not be wrong in.
_mtime() {
  local v
  v=$(stat -f %m -- "$1" 2>/dev/null) || v=""
  case "$v" in *[!0-9]*|'') v="" ;; esac
  if [ -n "$v" ]; then printf '%s' "$v"; return 0; fi
  stat -c %Y -- "$1" 2>/dev/null || echo ""
}

# THE PROGRESS ORACLE IS BORROWED, NOT RE-SPELLED. hooks/lib/engagement.sh is this box's ONE
# definition of "did a spawned Claude Code session actually run" (`assistant_turn_in`, parity-pinned
# byte-for-byte against scripts/handoff-fire.sh by tests/spawn-wedge-watchdog.bats) plus the ONE
# account-home list (`cc_engagement_homes`). Sourcing it means the day someone improves that
# predicate this detector improves with it; a private copy here would be the third spelling and the
# first to go stale (memory make-the-actuator-the-arbiter).
#
# ITS ABSENCE IS A MISSING TOOL, i.e. guard 1's case and NOT a conviction: a broken install must not
# make every chain read dead. Sourced with the shellcheck directive because the path is resolved at
# runtime and the file is not a static sibling of this one on every layer (the live ~/.claude tree
# reaches it through per-file symlinks).
_ENGAGE_LIB="$REPO/hooks/lib/engagement.sh"
[ -r "$_ENGAGE_LIB" ] || _ENGAGE_LIB="${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/hooks/lib/engagement.sh"
# shellcheck source=/dev/null
[ -r "$_ENGAGE_LIB" ] && . "$_ENGAGE_LIB" 2>/dev/null

# VERDICT + WHY are ONE pair computed once and rendered by every arm, so the number a gate refuses
# on, the number a row is filed with and the number a human reads are the same read of the same
# store. Two reads would be two populations five minutes apart.
VERDICT="alive"; WHY="skipped"; LIVE=0; BRIEF_AGE=-1; BRIEF=""; LEASES=0; CLOUD_LEASES=0
PROGRESS_AGE=-1; PANE=""; SID=""; TRANSCRIPT=""; PROGRESS_WHY=""

emit() { # render + exit, per mode. Called exactly once.
  case "$MODE" in
    json)
      jq -cn --arg v "$VERDICT" --arg w "$WHY" --arg b "$BRIEF" \
             --arg pn "$PANE" --arg sd "$SID" --arg tr "$TRANSCRIPT" --arg pw "$PROGRESS_WHY" \
             --argjson l "$LIVE" --argjson a "$BRIEF_AGE" --argjson c "$LEASES" \
             --argjson cl "$CLOUD_LEASES" \
             --argjson p "$PROGRESS_AGE" --argjson pm "$PROGRESS_MAX_AGE" \
             --argjson hg "$HANDOVER_GRACE" \
        '{verdict:$v, why:$w, live_rows:$l, brief:(if $b=="" then null else $b end),
          brief_age_s:(if $a < 0 then null else $a end), live_leases:$c, cloud_leases:$cl,
          progress_age_s:(if $p < 0 then null else $p end),
          progress_why:(if $pw=="" then null else $pw end),
          pane:(if $pn=="" then null else $pn end), sid:(if $sd=="" then null else $sd end),
          transcript:(if $tr=="" then null else $tr end),
          progress_max_age_s:$pm, handover_grace_s:$hg,
          note:"verdict alive|dead. why: drained = zero live rows, the SUCCESS state, never files; handover-grace = a recycle fired inside CC_DRAIN_HANDOVER_GRACE_S, the blind window at every handover where nothing about the successor is knowable yet; live-lease = a non-done row is claimed inside CC_BACKLOG_STALE_CLAIM_S BY A HOLDER THAT IS NOT venue:cloud (cloud_leases is counted separately and never proves THIS chain alive: Lane A claims oscillate claim->block->unblock->re-claim forever at 1 done per 17 dispatches, so a cloud lease is a constant and a constant disjunct carries no bits); progressing = the session that brief was fired into has a real assistant turn and a transcript younger than CC_DRAIN_PROGRESS_MAX_AGE_S; skipped/read-failed = could not ask, which is never a conviction. dead means the pile is non-empty and NOTHING is working it: no-brief-no-lease = no recycle inside CC_DRAIN_CHAIN_MAX_AGE_S; stalled = the fired session was found and is emitting nothing (the wedge); unverifiable = a fresh brief past the grace whose successor could not be resolved at all. A FRESH BRIEF IS NEVER SUFFICIENT ON ITS OWN — it is the age of a file the chain wrote when it last STARTED (backlog d6d4b85ebd4c)."}'
      exit 0 ;;
    assert)
      [ "$VERDICT" = dead ] || exit 0
      printf 'drain-chain-assert: %s\n' "$TITLE" >&2; exit 1 ;;
    report)
      if [ "$VERDICT" = dead ]; then printf 'drain-chain-assert: %s\n' "$TITLE"
      else printf 'drain-chain-assert: chain ALIVE (%s) · %s live row(s)%s%s\n' "$WHY" "$LIVE" \
             "$([ -n "$BRIEF" ] && printf ' · newest brief %ss old' "$BRIEF_AGE")" \
             "$([ "$PROGRESS_AGE" -ge 0 ] && printf ' · pane %s last emitted %ss ago' "$PANE" "$PROGRESS_AGE")"; fi
      exit 0 ;;
    file)
      [ "$VERDICT" = dead ] || exit 0
      [ -x "$BACKLOG_BIN" ] || { printf 'no cc-backlog at %s (fail-open)\n' "$BACKLOG_BIN" >&2; exit 0; }
      # `--falsifier` reaches a row only while CREATING it (cmd_add's update arm is deliberately a
      # no-op on a known id), so this attaches once, at first filing; `cc-backlog falsify` is the
      # verb for correcting it later. The TITLE, by contrast, IS kept current by the update arm —
      # which is why the live numbers belong there and not in the condition key.
      "$BACKLOG_BIN" add --project claude-infrastructure \
        --condition local-drain-chain-dead \
        --title "$TITLE" \
        --source drain-chain-assert \
        --falsifier "bash $HERE/drain-chain-assert.sh --assert" \
        --dod-ref "origin/main:docs/plans/BACKLOG_DRAIN_24_7.md" >/dev/null 2>&1 \
        || { printf 'drain-chain-assert: could not file the escalation row\n' >&2; exit 0; }
      exit 0 ;;
  esac
}

# TITLE is referenced by emit() in every arm, so it is defined before the first possible emit.
# Re-assigned once the live figures are known.
TITLE="the 24/7 backlog drain chain is not running"

# ── guard 1: can we ask at all? ────────────────────────────────────────────────────────────────
command -v jq >/dev/null 2>&1 || { WHY="skipped"; emit; }
[ -x "$BACKLOG_BIN" ]         || { WHY="skipped"; emit; }
# The engagement oracle is a TOOL by the same rule: without it the progress arm cannot ask, and "I
# could not ask" is never "the answer was no".
command -v assistant_turn_in   >/dev/null 2>&1 || { WHY="skipped"; emit; }
command -v cc_engagement_homes >/dev/null 2>&1 || { WHY="skipped"; emit; }

ROWS="$("$BACKLOG_BIN" list --open --json 2>/dev/null)" || ROWS=""
printf '%s' "$ROWS" | jq -e 'type=="array"' >/dev/null 2>&1 || { WHY="read-failed"; emit; }

LIVE="$(printf '%s' "$ROWS" | jq 'length')"
case "$LIVE" in ''|*[!0-9]*) WHY="read-failed"; LIVE=0; emit ;; esac

# ── guard 2: an empty pile is the SUCCESS state, and success must not file a row ───────────────
[ "$LIVE" -gt 0 ] || { WHY="drained"; emit; }

# ── disjunct A: a fire-drain-recycle-N brief younger than MAX_AGE (§4.1's path) ────────────────
# Newest match wins. The glob is unquoted ON PURPOSE — that is the expansion — and `nullglob` keeps
# a no-match from handing the literal pattern to stat as a filename.
shopt -s nullglob
while IFS= read -r _g; do
  [ -n "$_g" ] || continue
  for _f in $_g; do
    [ -f "$_f" ] || continue
    _m="$(_mtime "$_f")"
    case "${_m:-}" in ''|*[!0-9]*) continue ;; esac
    _age=$(( NOW - _m ))
    [ "$_age" -lt 0 ] && _age=0        # a clock skew is not a fresh brief, but it is not -1 either
    if [ "$BRIEF_AGE" -lt 0 ] || [ "$_age" -lt "$BRIEF_AGE" ]; then BRIEF_AGE="$_age"; BRIEF="$_f"; fi
  done
done <<EOF
$BRIEF_GLOB
EOF
shopt -u nullglob

# A fresh brief is a NECESSARY condition and never a sufficient one — see the header. `FRESH` gates
# the two arms below that can only speak about a chain that has recycled at all.
FRESH=0
if [ "$BRIEF_AGE" -ge 0 ] && [ "$BRIEF_AGE" -lt "$MAX_AGE" ]; then FRESH=1; fi

# ── disjunct A0: the HANDOVER GRACE — the blind window at every recycle ────────────────────────
# Checked FIRST and before any resolution is attempted, because during it the registry row is mid-
# rewrite and the successor's transcript may not exist: every hop of the progress oracle answers
# "no" for a perfectly healthy chain. Bounded by construction — a wedged successor fires nothing, so
# its brief ages out of the grace within CC_DRAIN_HANDOVER_GRACE_S and the progress arm resumes.
if [ "$FRESH" = 1 ] && [ "$BRIEF_AGE" -lt "$HANDOVER_GRACE" ]; then WHY="handover-grace"; emit; fi

# ── disjunct B: somebody holds a live lease ────────────────────────────────────────────────────
# `lastTs` is ISO-8601 from the fold; `fromdateiso8601` in jq, and a row whose stamp will not parse
# is counted as NOT a live lease — it cannot prove aliveness, and disjunct B is the arm that has to
# PROVE something for the alarm to stay silent.
#
# THE VENUE SPLIT (arm (b) in the header). `venue` is written by `cc-backlog claim` itself and is
# already in the fold — 744 `cloud` / 88 `local` / 2224 legacy-absent over the whole ledger — so this
# is a read of the store's own field, not a second state model of it. Only an EXPLICIT `cloud` is
# subtracted; absent and every other spelling still counts, so an unreadable or unfamiliar venue
# abstains toward ALIVE exactly as guard 3 requires. The cloud figure is kept, not discarded: it is
# reported and it goes into the dead title, because a "nothing is working them" claim that silently
# drops a stratum is the defect `zero-claim-must-name-its-excluded-strata` names.
_lease_count() { # <jq-select-expr> → count, or 0 on any unreadable fold
  local n
  n="$(printf '%s' "$ROWS" | jq --argjson now "$NOW" --argjson ttl "$STALE_CLAIM" "
    [ .[]
      | select(.status == \"claimed\")
      | select( ((.lastTs // \"\") | if . == \"\" then null else (try fromdateiso8601 catch null) end)
                as \$t | \$t != null and (\$now - \$t) < \$ttl )
      | select($1) ] | length" 2>/dev/null)"
  case "${n:-}" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s' "$n"
}
LEASES="$(_lease_count '(.venue // "") != "cloud"')"
CLOUD_LEASES="$(_lease_count '(.venue // "") == "cloud"')"
if [ "$LEASES" -gt 0 ]; then WHY="live-lease"; emit; fi

# ── disjunct A: is the session that brief was fired into STILL PROGRESSING? ────────────────────
# Sets PANE / SID / TRANSCRIPT / PROGRESS_AGE / PROGRESS_WHY and returns 0 only when it reached a
# transcript. PROGRESS_WHY names the hop that failed, so an `unverifiable` row says WHICH link of
# the chain was missing rather than sending its reader back to re-derive it.
_resolve_progress() {
  local row f home
  PROGRESS_WHY="no-brief"
  [ -n "$BRIEF" ] || return 1

  # hop 1 — brief → the pane it was fired into. handoffs.jsonl carries one row per fire with the
  # `prompt_file` verbatim, so the join is on the very file whose age we just measured rather than
  # on "whatever pane looks like a drain". LAST match wins: a brief path can be re-fired.
  #
  # THE EXACT-PATH JOIN IS NECESSARY AND NO LONGER SUFFICIENT. The live chain fires with a 152-byte
  # POINTER (`fire-pointer-<N>.txt`, "read fire-drain-recycle<N>.txt in full") because the brief
  # outgrew a promptable payload, so handoffs.jsonl records the pointer and the exact match against
  # the brief can never fire. The fallback joins on the RECYCLE NUMBER — the digit run in each
  # basename — which is the class, not a list of the four spellings observed so far
  # (`fire-drain-recycle<N>.txt`, `…<N>.pointer.txt`, `…<N>-pointer.txt`, `fire-pointer-<N>.txt`);
  # enumerating those is the `denylist-enumerates-spellings-not-the-class` defect and the fifth
  # spelling would be silently blind again. Exact match still wins where it exists, so a chain that
  # fires the brief directly is unaffected.
  PANE="${CC_DRAIN_PANE:-}"
  if [ -z "$PANE" ]; then
    PROGRESS_WHY="no-handoff-log"
    [ -r "$HANDOFF_LOG" ] || return 1
    PANE="$(jq -r --arg b "$BRIEF" 'select((.prompt_file? // "") == $b)
                                    | (.target_pane? // empty)' "$HANDOFF_LOG" 2>/dev/null | tail -1)"
    if [ -z "$PANE" ]; then
      local num
      num="$(printf '%s' "${BRIEF##*/}" | tr -dc '0-9')"
      if [ -n "$num" ]; then
        PANE="$(jq -r --arg n "$num" '
          (.prompt_file? // "") as $p
          | select($p != "")
          | ($p | split("/") | last | gsub("[^0-9]"; "")) as $m
          | select($m == $n)
          | (.target_pane? // empty)' "$HANDOFF_LOG" 2>/dev/null | tail -1)"
      fi
    fi
  fi
  PROGRESS_WHY="no-fire-row-for-brief"
  [ -n "$PANE" ] || return 1
  # The pane id is about to be interpolated into a PATH. Same guard, same reason as
  # handoff-fire.sh's own stamp writer: anything but a kitty-window-id / paneUUID shape is refused
  # outright rather than allowed to name a file.
  case "$PANE" in *[!0-9A-Za-z-]*) PROGRESS_WHY="pane-id-not-id-shaped"; PANE=""; return 1 ;; esac

  # hop 2 — pane → the live session id. A missing row is the startup modal's OWN signature
  # (SessionStart never fires behind a blocking dialog), which is why this resolves to a DEAD
  # `unverifiable` past the grace and not to an abstention.
  PROGRESS_WHY="no-registry-row"
  row="$REGISTRY_DIR/$PANE.json"
  [ -f "$row" ] || return 1
  SID="$(jq -r '.session_id // empty' "$row" 2>/dev/null)"
  PROGRESS_WHY="row-without-session-id"
  [ -n "$SID" ] || return 1

  # hop 3 — sid → its transcript, in whichever account home holds it. `cc_engagement_homes` is
  # SOURCED from hooks/lib/engagement.sh rather than re-spelled: a second copy of the account-home
  # list is exactly how sibling auditors drift (memory sibling-auditors-must-share-the-state-model).
  PROGRESS_WHY="no-transcript"
  while IFS= read -r home; do
    [ -n "$home" ] || continue
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      TRANSCRIPT="$f"; break
    done <<EOF
$(find "$home/projects" -name "$SID.jsonl" -type f 2>/dev/null)
EOF
    [ -n "$TRANSCRIPT" ] && break
  done <<EOF
$(cc_engagement_homes)
EOF
  [ -n "$TRANSCRIPT" ] || return 1

  # hop 4 — BIRTH IS NOT ENGAGEMENT. A transcript exists from the session's first system row, so an
  # mtime alone would call a pane that has done nothing a working one. The parity-pinned oracle is
  # the same one handoff-fire and cc-wedge-watch use.
  PROGRESS_WHY="transcript-without-assistant-turn"
  assistant_turn_in "$TRANSCRIPT" || return 1

  local m
  m="$(_mtime "$TRANSCRIPT")"
  PROGRESS_WHY="transcript-mtime-unreadable"
  case "${m:-}" in ''|*[!0-9]*) return 1 ;; esac
  PROGRESS_AGE=$(( NOW - m ))
  [ "$PROGRESS_AGE" -lt 0 ] && PROGRESS_AGE=0
  PROGRESS_WHY="resolved"
  return 0
}

if [ "$FRESH" = 1 ]; then
  _resolve_progress
  if [ "$PROGRESS_AGE" -ge 0 ] && [ "$PROGRESS_AGE" -lt "$PROGRESS_MAX_AGE" ]; then
    WHY="progressing"; emit
  fi
fi

# ── nothing proved aliveness: the pile is non-empty and nothing is working it ──────────────────
# Three distinguishable dead states, and the title says which — a false row must be diagnosable
# from the row itself.
VERDICT="dead"
# NAME THE EXCLUDED STRATUM IN THE TITLE. "Nothing is working them" is false-sounding to anyone who
# can see live cloud claims, and a reader who cannot reconcile the two re-derives the whole thing.
# Empty when there is nothing to disclose, so the ordinary title does not carry dead words.
CLOUD_CLAUSE=""
[ "$CLOUD_LEASES" -gt 0 ] && CLOUD_CLAUSE="$(printf ' (%s live venue:cloud lease(s) are held and deliberately do NOT count: Lane A claims oscillate claim->block->unblock->re-claim without landing, so they are live around the clock and prove nothing about THIS chain — DRAIN_CIRCUIT_2026-09-01 §1.3)' "$CLOUD_LEASES")"
if [ "$FRESH" != 1 ]; then
  WHY="no-brief-no-lease"
  TITLE="$(printf 'the 24/7 backlog drain chain is DEAD — %s live row(s) and nothing is working them: no fire-drain-recycle brief inside %ss (newest: %s) and 0 live leases inside %ss. Restart it with the Lane B recycle-fire template in docs/plans/BACKLOG_DRAIN_24_7.md §4.1' \
    "$LIVE" "$MAX_AGE" \
    "$([ "$BRIEF_AGE" -ge 0 ] && printf '%ss old' "$BRIEF_AGE" || printf 'none')" \
    "$STALE_CLAIM")$CLOUD_CLAUSE"
elif [ "$PROGRESS_AGE" -ge 0 ]; then
  WHY="stalled"
  TITLE="$(printf 'the 24/7 backlog drain chain is DEAD — %s live row(s) and nothing is working them: the recycle fired %ss ago into pane %s is WEDGED, emitting nothing for %ss (ceiling %ss, transcript %s) and holding 0 live leases inside %ss. A fresh brief only proves the chain last STARTED. Clear the pane (a PreToolUse modal no agent can answer is the measured cause — backlog 7da9c4451540) and restart it with the Lane B recycle-fire template in docs/plans/BACKLOG_DRAIN_24_7.md §4.1' \
    "$LIVE" "$BRIEF_AGE" "$PANE" "$PROGRESS_AGE" "$PROGRESS_MAX_AGE" "$TRANSCRIPT" "$STALE_CLAIM")$CLOUD_CLAUSE"
else
  WHY="unverifiable"
  TITLE="$(printf 'the 24/7 backlog drain chain is DEAD — %s live row(s) and nothing is working them: a fire-drain-recycle brief %ss old (%s) whose successor CANNOT BE RESOLVED (%s), 0 live leases inside %ss, and the %ss handover grace has expired. Restart it with the Lane B recycle-fire template in docs/plans/BACKLOG_DRAIN_24_7.md §4.1' \
    "$LIVE" "$BRIEF_AGE" "$BRIEF" "$PROGRESS_WHY" "$STALE_CLAIM" "$HANDOVER_GRACE")$CLOUD_CLAUSE"
fi
emit
