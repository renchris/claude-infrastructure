#!/usr/bin/env bash
# waiting-recycle.sh — auto-recycle a MONITORING DESK when it is purely WAITING at MODERATE context.
#
# THE PROBLEM (operator, 2026-07-17): an orchestrator DESK that fires sessions and then WATCHES them
# fills with low-value watch noise. Context rot degrades instruction-following + state-recall well
# before the 90% auto-compact wall (noticeable ~40-50%, compounding past ~60-70%) and hits the
# "lost in the middle" load-bearing orchestration decisions. So a monitoring desk should recycle
# MORE AGGRESSIVELY than a builder — at a MODERATE threshold, at a quiet boundary, into a fresh
# successor that carries the state forward (the recycled pane IS the continuation).
#
# WHY A NEW HOOK, NOT boundary-handoff.sh (which already advises /handoff at a threshold):
#   boundary-handoff.sh fires on the **Stop** event. A watch-driven desk polling in a long turn (or
#   held open by session-continue's loose-ends loop) NEVER cleanly Stops, so that advisory never
#   lands and the desk OVER-ACCUMULATES (boundary-handoff's own B-1 header names this blind spot; the
#   out-of-session lead-supervisor.sh covers 'past-threshold ∧ not-Stopping' but can only PAGE — bash
#   cannot drive a live pane). This hook is the IN-SESSION carrier for exactly that case: it fires on
#   the desk's MONITORING CADENCE — PostToolUse:Bash, the heartbeat of a polling desk — so it reaches
#   the desk between polls, not only at a Stop it never hits.
#
# TWO-STAGE ACTUATION (Fable design panel 2026-07-19 — was advisory-ONLY, which fired 0/2419 in prod
# because the fire depended on the model NOTICING + complying):
#   STAGE 1 (advisory) — the FIRST fire-worthy poll ADVISES the model to run /handoff →
#     handoff-fire.sh --recycle (the model authors the richest payload) and starts a grace clock.
#   STAGE 2 (deterministic fire) — if the desk is STILL fire-worthy after GRACE_S (the model ignored
#     the advisory — i.e. it rotted past acting on it), the hook FIRES handoff-fire.sh --recycle
#     ITSELF with a composed brief (standing --brief template + frozen DoD + a re-derive-from-disk
#     directive; a MONITORING desk's watch-state is disk-reconstructible, so the successor is never
#     task-less). Stage 2 is cap+cooldown EXEMPT (bounded instead by a one-fire-per-SID latch — a
#     non-exempt Stage 2 would be silenced by the MAX-advisory cap: the panel's cap-trap).
#   SHADOW by default (arm) — Stage 2 LOGS a would-fire but does NOT exec until `arm --live`. Ships
#     the mechanism DAMPED so a gate bug cannot strand the fleet before the operator soaks the log.
#
# COMPOSES (reuse, not reinvent): boundary-handoff.sh's telemetry reader (used_pct freshness) ·
# anti-deference-nudge.sh's transcript-tell + genuine-carve-out + fail-safe + IDL discipline ·
# session-continue.sh's agent-armed-sentinel model (the agent declares intent; the hook is a dumb
# actuator) · the /handoff → handoff-fire.sh --recycle recycle path (unchanged).
#
# FIRE PREDICATE — ALL must hold (bias: FALSE-NEGATIVE over FALSE-POSITIVE; a missed recycle just
# waits for the threshold, a wrong recycle interrupts a healthy desk):
#   1. ARMED — the desk opted in via `waiting-recycle.sh arm` (sentinel keyed by cwd, survives a
#      recycle) OR it HOLDS the monitoring-desk role (cc-roles/<desk> resolves to this pane's uuid/sid
#      ⇒ ARM-BY-DEFAULT, G-P11-7): deterministic arming kills the "arm step is itself model-diligence"
#      root (0/2419 prod fires decomposed as 1977 not-armed). A builder (no arm sentinel, not the desk
#      role) is still never touched. Role-arm defaults to SHADOW (the live_for sentinel still gates the
#      exec — damp-first). Kill-switch: `clear` (per-desk, writes a durable disarm marker that also
#      suppresses arm-by-default) / `kill` (global). An explicit `arm` removes a prior disarm.
#   2. NOT globally killed — the blanket opt-out file ($CC_WR_KILL) is absent.
#   3. NOT in cooldown — no advisory for this cwd within COOLDOWN_S. This is the anti-thrash pacer AND
#      the cross-session LOOP-BREAKER: a fresh recycled desk (same cwd) sees the predecessor's cooldown
#      stamp and stays quiet, so recycle→fresh→recycle can't spin.
#   4. TRIGGER — context used_pct ≥ eff_idle (the ADAPTIVE idle threshold: base T_IDLE=35, decaying toward
#      T_IDLE_FLOOR=25 the longer this SID sits idle below it — proactive; recycling an IDLE desk is a FREE
#      WIN, no work in hand to lose, so we don't wait for 55%), OR a behavioral ROT tell in the last message
#      that ALSO clears used_pct ≥ ROT_FLOOR on FRESH telemetry (an un-floored tell false-positives on
#      healthy watch narration — probe P1 2026-07-19; a floored tell can fire below the threshold),
#      OR the SIZE axis (§9) — transcript bytes ≥ SIZE_MB, which is orthogonal to used_pct.
#   5. SAFE vs BUSY — the desk is CLASSIFIED, not just gated. SAFE (idle, just-waiting) ⇒ recycle. BUSY
#      holds are split soft/hard (see §7): 5a clean git tree (dirty=SOFT) + no sequencer state (MERGE_HEAD/
#      rebase/cherry-pick=HARD, S1); 5b no open decision (HARD — anti-deference's GENUINE carve-out); 5c no
#      active COORDINATION — a peer contract-BLOCKED on this desk (S3, SOFT), a fresh inbound mailbox line
#      (S4, SOFT — dispatch workers notify without a contract), a live context-bound teammate (S5, HARD:
#      results route to the dying SID). The desk's OWN waiter-contracts do NOT hold (durable on disk).
#   6. Under the per-session advisory CAP (Stage 1 only; Stage 2 is cap-exempt, latch-bounded). WEDGE
#      ESCALATION (T-P1-8): a fire-worthy-and-just-waiting desk that has exhausted its recycle attempts
#      (advisory CAP reached, or a SHADOW would-fire already latched) does NOT silently ride to the 90%
#      auto-compact wall — it PAGES the operator out-of-band (osascript + push-critical + an `escalated`
#      IDL record + a decision:block advisory), page-once per ESCALATE_DEDUP_S. Paging is fleet-safe, so
#      the escalation ships LIVE (unlike the Stage-2 exec, which stays SHADOW until armed --live).
#   7. TIERED CONTEXT-REFRESH (operator 2026-07-19, cc-backlog 4ce6ffc0194f) — once fire-worthy, route on
#      desk STATE (the evidence: a desk sat low-context for hours then hit 74% MID-work, an awkward recycle):
#        • IDLE (SAFE)                       → recycle at the lowered ADAPTIVE T_IDLE (§4). Tiers 1–2.
#        • BUSY soft + HIGH ctx (≥ T_BUSY=75)→ FORCE-recycle, DRAINING the pending pings (mailbox + inbound
#          wait-contracts) into the successor brief so NONE are dropped (Tier 3). SHADOW-default: composes
#          the drained brief + PAGES (fleet-safe, ships LIVE); the EXEC is opt-in beyond --live (--busy-force).
#        • BUSY hard + HIGH ctx              → PAGE (a sequencer/teammate/open-decision recycle would lose
#          state or bury a decision — surface, never force).
#        • BUSY + medium/low                 → Tier 2: mark a refresh-queued intent + hold; the lowered idle
#          threshold fires it at the next idle gap (context grows monotonically, so it converges there).
#      All new aggressiveness is advisory or SHADOW+page by default — nothing auto-execs until armed
#      (idle: --live; busy: --live --busy-force). Damp-first, unchanged from the Stage-2 discipline.
#   8. CONTEXT-ECON SIGNALS (2026-07-20 — docs/research/context-econ-2026-07-20.md) — three continuous
#      signals sharpen the tiers, from hooks/lib/context-econ.sh; ANY unknown signal degrades to the
#      exact legacy behavior (false-negative bias kept):
#        • S6 CONVERSATION-HOLD (SOFT) — a fresh INTERACTIVE turn (< CONV_HOLD_S) marks a live 2-way
#          exchange: HIGH-VALUE context that leaves NO git/mailbox trace (the "74% mid-conversation"
#          incident — S1–S5 read it as idle). Auto-drive re-prompts (session-continue 🔧 / goal Stop
#          feedback) are excluded on two axes, so an auto-driven desk still free-wins. Just ABOVE that
#          window (CONV_HOLD_S ≤ age < CONV_RECENT_S) the exchange only just quieted, so the IDLE
#          Stage-2 fire waits the longer RECENT_GRACE_S (not GRACE_S=180) before discarding it.
#        • FORECAST-EARLY busy trigger — used ≥ T_BUSY_MIN AND burn-forecast ≤ LEAD_MIN minutes to the
#          wall ⇒ the busy ladder (advisory→drain) starts BEFORE T_BUSY; at high burn the wall arrives
#          first. Exec gating unchanged (--live --busy-force).
#        • PAUSE-POINT NUDGE — BUSY soft-held ≥ T_NUDGE gets a PACED advisory to plan its own boundary
#          (commit → persist → /handoff) instead of silent Tier-2; the model is the pause-point judge.
#          Re-arms per +NUDGE_REARM pct fill (the boundary-handoff B-2 shape); never fires a recycle.
#   9. SIZE AXIS (2026-07-29, K02 — audit raw/a12.md K02 + raw/a3.md S1/S2) — every trigger in §4/§8 keys
#      on used_pct, the CONTEXT WINDOW's occupancy. Compaction resets it; the cumulative transcript and the
#      process footprint do NOT. So this hook was SIZE-BLIND: a3 measured 0 fires across its entire deployed
#      life while sessions carried tens of MB of transcript, and — the sharper half of that finding — the
#      ENTIRE apparatus (advisory, Stage 2, wedge page, busy page) sits DOWNSTREAM of the
#      `below-threshold-no-tell` abstain, so a size-dangerous session at low fill exited before reaching
#      even the out-of-band operator page. Two independent metrics (measured pearson +0.26 — neither is a
#      proxy for the other; the falsified `input_tokens` premise is refuted in hooks/lib/context-econ.sh):
#        • TRANSCRIPT BYTES ≥ SIZE_MB → a full trigger: it joins the §4 gate as a third disjunct AND sets
#          high_ctx, so it routes through the EXISTING tiers by construction — SAFE ⇒ the idle Stage-1→2
#          recycle ladder; BUSY soft ⇒ the Tier-3 drain (shadow-composes + pages, exec still needs
#          --live --busy-force); BUSY hard ⇒ the busy-page. The roadmap's "emergency page fallback" is
#          therefore not new machinery — it falls out of the tiers already here. Bytes may drive the exec
#          because a recycle is the ONLY thing that resets them (fresh SID ⇒ fresh JSONL at 0; /compact
#          does not shrink the file), and because the axis is monotonic there is nothing to re-arm on.
#        • RSS ≥ RSS_PAGE_MB → PAGE ONLY, never an auto-recycle, and only when it is the SOLE signal (any
#          other trigger routes to the ladder, which has an actual lever). Rationale, not squeamishness:
#          every live session already sits ≥431 MB with the observed max at 1000 MB, and the DANGEROUS
#          level is unknown (the 07-22 diagnosis records the per-process death mechanism as UNPROVEN and
#          that crash class was later superseded by a CC-version regression). Auto-recycling the fleet on a
#          guessed RSS number is a hazard with no evidence behind it — so it pages, and every eval records
#          the measured value so the threshold gets calibrated from data instead of promoted on a guess.
#      Both thresholds default DORMANT against the measured live fleet (0/29 sessions fire at 25 MB /
#      1500 MB; live max 22.4 MB / 1000 MB) — they catch the next real giant without touching today's
#      fleet. Every IDL record from here on carries tx_mb + rss_mb, fired or abstained, so a dormant
#      threshold is never indistinguishable from broken wiring.
#
# Delivery: {decision:"block"} + hookSpecificOutput.additionalContext (the MODEL-facing recycle
# advisory — confirmed delivered on PostToolUse @ 2.1.183) + systemMessage/reason (operator-facing).
# The tool has ALREADY run at PostToolUse, so a fire can NEVER break the recycle machinery it triggers
# (unlike a PreToolUse deny). Exit 0 ALWAYS — a PostToolUse hook must never cost a session.
#
# Agent/operator CLI (run from the desk's worktree):
#   waiting-recycle.sh arm      # opt IN this desk (keyed by cwd) — also removes a prior `clear` disarm
#   waiting-recycle.sh clear    # opt OUT this desk (per-desk kill-switch: writes a durable disarm marker
#                               #   that ALSO suppresses arm-by-default) + reset its cooldown/cap
#   waiting-recycle.sh status   # inspect this desk's arm/disarm/cooldown/cap + global kill state
#   waiting-recycle.sh kill      # GLOBAL blanket off (all sessions)
#   waiting-recycle.sh unkill    # remove the global kill-switch
# Claude Code calls it with NO args + the PostToolUse JSON on stdin → actuation mode.
#
# Agent/operator CLI (extended): arm [--brief <file>] [--live] [--busy-force]  — --brief seeds the Stage-2
#   successor prompt; --live enables the idle Stage-2 EXEC (requires a non-empty --brief; default SHADOW);
#   --busy-force ALSO enables the Tier-3 BUSY+HIGH mid-work forced-recycle EXEC (requires --live).
#
# Env seams (tests): CC_WR_T (alias→T_IDLE) · CC_WR_T_IDLE · CC_WR_T_BUSY · CC_WR_T_IDLE_FLOOR ·
#                    CC_WR_IDLE_DECAY_S · CC_WR_BUSY_FORCE · CC_TELEMETRY_DIR · CC_WR_AGE_MAX · CC_WR_IDL ·
#                    CC_WR_STATE_DIR · CC_WR_MAX · CC_WR_COOLDOWN_S · CC_WR_KILL · CC_WR_ROT_FLOOR ·
#                    CC_WR_GRACE_S · CC_WR_COORD_DIR · CC_WR_UUID · CC_WR_QUIET_S · CC_WR_FIRE_DIR ·
#                    CC_WR_HANDOFF_FIRE · CC_WR_DESK_ROLE · CC_WR_NOTIFY · CC_WR_PUSH · CC_WR_ESCALATE_DEDUP_S ·
#                    CC_WR_CONV_HOLD_S · CC_WR_CONV_RECENT_S · CC_WR_RECENT_GRACE_S · CC_WR_T_BUSY_MIN · CC_WR_LEAD_MIN · CC_WR_T_NUDGE · CC_WR_NUDGE_REARM ·
#                    CC_WR_SIZE_MB · CC_WR_RSS_PAGE_MB · CC_WR_TAIL_BYTES (M13 bounded transcript reads;
#                      0 / set-but-empty / non-numeric ⇒ the incumbent unbounded read) ·
#                    WRC_OSA_TIMEOUT_S · WRC_OSA_TIMEOUT_BIN (osascript fork bound; empty ⇒ unbounded) ·
#                    CC_CE_* (context-econ lib: WIN_S / WALL / MIN_SPAN_S / HIST_MAX / TAIL_BYTES / AUTO_RX / PS / RSS_COMM_RX)
#
# NOTE: deliberately NO `set -e` — a hook must fail SAFE (abstain), and a stray non-zero from a grep
# test must never become the script's exit code and suppress a legitimate abstain-log. -u/pipefail are
# on for hygiene; every path ends `exit 0`.
set -uo pipefail

# Bound the OS-notification fork (machine-wide iTerm2/AppleEvent wedge, 2026-07-26). This one
# targets NotificationCenter rather than iTerm2, so it is not the root cause — but it is an
# AppleEvent fork inside an automated path, and an unbounded one turns a best-effort page into a
# stalled hook. Every call site here is already best-effort (`|| true`), so a cut costs at most
# one missed notification and never a wrong verdict. timeout(1) is resolved by ABSOLUTE PATH as
# well as PATH — hooks and launchd jobs run without Homebrew on PATH, where coreutils installs it.
# No timeout(1) ⇒ run unbounded rather than lose notifications entirely.
# Seams: WRC_OSA_TIMEOUT_S · WRC_OSA_TIMEOUT_BIN (set-but-EMPTY disables verbatim).
WRC_OSA_TIMEOUT_S="${WRC_OSA_TIMEOUT_S:-5}"
if [ -n "${WRC_OSA_TIMEOUT_BIN+set}" ]; then
  WRC_OSA_TB="${WRC_OSA_TIMEOUT_BIN}"
else
  WRC_OSA_TB=""
  for _c in "$(command -v timeout 2>/dev/null || true)" "$(command -v gtimeout 2>/dev/null || true)" \
            /opt/homebrew/bin/timeout /usr/local/bin/timeout \
            /opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout; do
    [ -n "$_c" ] && [ -x "$_c" ] && { WRC_OSA_TB="$_c"; break; }
  done
fi
wrc_osa() {
  if [ -z "$WRC_OSA_TB" ] || [ ! -x "$WRC_OSA_TB" ]; then "$@"; return $?; fi
  "$WRC_OSA_TB" -k 3 "$WRC_OSA_TIMEOUT_S" "$@"
}


# ── TIERED CONTEXT THRESHOLDS (operator 2026-07-19, cc-backlog 4ce6ffc0194f) ──────────────────────
# A monitoring desk fills with low-value watch noise; recycling at an IDLE (just-waiting) boundary is
# a FREE WIN — no work in hand to lose (state is disk-reconstructible), and it sheds the rot BEFORE it
# reaches the awkward busy-and-high case (the evidence: a desk sat low-context for hours, then hit 74%
# MID-conversation). So the single 55% gate is split into two state-keyed thresholds:
#   • IDLE (SAFE gate passes — just waiting)  → recycle at the LOWER, ADAPTIVE T_IDLE (proactive).
#   • BUSY (SAFE gate fails — mid-work/coord) → hold as before UNTIL context reaches the HIGH T_BUSY,
#     where a forced path drains the pending pings into the successor brief (never a silent ride to the
#     90% auto-compact wall). See the decision-routing block below.
# CC_WR_T stays a back-compat alias: if set, it seeds T_IDLE (old callers pinning 55 keep a 55 idle bar).
T_IDLE="${CC_WR_T_IDLE:-${CC_WR_T:-35}}"                     # IDLE recycle threshold (was 55; lowered — proactive)
T_BUSY="${CC_WR_T_BUSY:-75}"                                 # BUSY forced-recycle threshold (Tier 3; just above the observed-awkward 74%)
T_IDLE_FLOOR="${CC_WR_T_IDLE_FLOOR:-25}"                     # adaptive decay floor (== ROT_FLOOR: the two triggers converge here)
IDLE_DECAY_S="${CC_WR_IDLE_DECAY_S:-3600}"                   # T_IDLE decays to the floor over THIS long-idle window (0 ⇒ no decay)
ROT_FLOOR="${CC_WR_ROT_FLOOR:-25}"                          # rot-tell needs THIS much fill to be real
AGE_MAX="${CC_WR_AGE_MAX:-180}"                             # telemetry older than this can't be trusted
MAX="${CC_WR_MAX:-3}"                                       # per-session advisory cap (never nag forever)
COOLDOWN_S="${CC_WR_COOLDOWN_S:-600}"                       # cwd-keyed anti-thrash + cross-session loop-breaker
TEL_DIR="${CC_TELEMETRY_DIR:-/tmp/cc-telemetry}"            # shared with boundary-handoff / statusline
IDL="${CC_WR_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
STATE_DIR="${CC_WR_STATE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/state/waiting-recycle}"
KILL="${CC_WR_KILL:-$STATE_DIR/OFF}"                        # global blanket kill-switch
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
DESK_ROLE="${CC_WR_DESK_ROLE:-desk}"                       # G-P11-7: role a monitoring desk holds → arm-by-default
# Desk-identity roots — HOISTED above the CLI dispatch (2026-07-26) because the sentinel resolver below
# now consults the role, and `arm`/`clear`/`status` run BEFORE the hook path parses stdin. Left where it
# was, `waiting-recycle.sh arm --live` from a desk would not see the role and would write a cwd-keyed
# sentinel — the exact fragility this change removes. COORD is a FIXED path (cc-roles lives at
# $HOME/.claude, NOT $CLAUDE_CONFIG_DIR) so identity survives a config-dir migration.
COORD="${CC_WR_COORD_DIR:-$HOME/.claude}"                    # root of wait-contracts/ mailbox/ cc-roles/
UUID="${CC_WR_UUID:-${ITERM_SESSION_ID:-}}"; UUID="${UUID##*:}"   # this desk's iTerm pane uuid (survives recycle)
SID="${SID:-}"                                               # set by the hook path; empty on the CLI path
# G-P11-7: is THIS session the monitoring desk? (cc-roles/<DESK_ROLE> resolves to its uuid or sid).
# UUID is resolved lazily too, so this answers correctly on BOTH the CLI and hook paths.
is_monitoring_desk() {
  local rf="$COORD/cc-roles/$DESK_ROLE" rv u="$UUID"
  [ -n "$u" ] || { u="${CC_WR_UUID:-${ITERM_SESSION_ID:-}}"; u="${u##*:}"; }
  [ -f "$rf" ] || return 1
  rv="$(head -1 "$rf" 2>/dev/null | tr -d '[:space:]')"; [ -n "$rv" ] || return 1
  { [ -n "$SID" ] && [ "$rv" = "$SID" ]; } || { [ -n "$u" ] && [ "$rv" = "$u" ]; }
}
NOTIFY_CMD="${CC_WR_NOTIFY:-}"                              # T-P1-8: empty → builtin osascript operator page
PUSH_BIN="${CC_WR_PUSH:-$CFG/hooks/push-critical.sh}"      # T-P1-8: Pushover break-through (INERT unless armed)
ESCALATE_DEDUP_S="${CC_WR_ESCALATE_DEDUP_S:-900}"          # T-P1-8: page-once cadence while a desk stays wedged

# ── CONTEXT-ECON knobs (2026-07-20 — docs/research/context-econ-2026-07-20.md, header §8) ─────────
CONV_HOLD_S="${CC_WR_CONV_HOLD_S:-900}"                    # S6: a fresh interactive turn holds a free-win recycle this long
T_BUSY_MIN="${CC_WR_T_BUSY_MIN:-60}"                       # forecast-early busy trigger never fires below this fill
LEAD_MIN="${CC_WR_LEAD_MIN:-20}"                           # burn-forecast ≤ this many minutes to the wall ⇒ act early while BUSY
T_NUDGE="${CC_WR_T_NUDGE:-50}"                             # BUSY pause-point-planning advisory from this fill upward
NUDGE_REARM="${CC_WR_NUDGE_REARM:-10}"                     # re-nudge per +N pct fill climb (B-2 shape)
CONV_RECENT_S="${CC_WR_CONV_RECENT_S:-7200}"              # recent-conversation grace window: an interactive turn within this
                                                          #   (but past CONV_HOLD_S — S6 no longer holds) extends the idle Stage-2 grace
RECENT_GRACE_S="${CC_WR_RECENT_GRACE_S:-900}"            # …to THIS (vs GRACE_S=180) — don't discard a just-quieted exchange too fast

# ── SIZE-AXIS knobs (2026-07-29, K02 — header §9) ─────────────────────────────────────────────────
# Defaults are DORMANT against the measured live fleet (0/29 sessions fire; live max 22.4 MB / 1000 MB
# RSS, p90 5.1 MB / 918 MB) — deliberately: a threshold that fires on today's healthy fleet is a
# fleet-wide recycle storm, and the IDL now records tx_mb/rss_mb on every eval so these get calibrated
# DOWN from observed data rather than guessed. SIZE_MB=0 or RSS_PAGE_MB=0 disables that axis outright.
SIZE_MB="${CC_WR_SIZE_MB:-25}"                            # transcript bytes ≥ this many MB ⇒ full trigger (may recycle)
RSS_PAGE_MB="${CC_WR_RSS_PAGE_MB:-1500}"                  # process RSS ≥ this many MB ⇒ PAGE ONLY, never an auto-recycle

# Per-cwd key (arm + cooldown survive a recycle since cwd is stable across it); per-session key (cap
# resets on the fresh successor). Mirrors session-continue.sh's config-dir|path hash.
key_cwd() { printf '%s|%s' "$CFG" "$1" | shasum 2>/dev/null | cut -c1-16; }
# ROLE-KEYED identity (2026-07-26). The desk's identity is a ROLE FILE, not a directory — but these six
# sentinels were keyed on (cfg,cwd), so they only resolved because desk-invariant happens to respawn with
# a fixed `--cwd $CANNED_CWD`. A desk started by hand (`desk-register` exists precisely for that) from any
# other directory found NO sentinel and silently fell back to the default — and the default for `live` is
# SHADOW, i.e. log the recycle it would have fired and do nothing. Silent, and off.
#
# Keyed on the ROLE NAME (not the pane uuid) so every pane that ever holds the role shares one setting.
#
# READ ORDER IS FAIL-SAFE AND DELIBERATE: role-keyed first, then the legacy (cfg,cwd) path. That makes the
# resolver strictly MORE likely to find existing state, never less — so this change cannot silently switch
# off an opt-in that was on. It is safe in the same direction for all six: `live`/`arm` finding state means
# armed; `disarm`/`cooldown` finding state means SUPPRESSED. Both directions err toward the status quo.
# New writes go role-keyed, so state migrates forward as it is touched (no migration script, no flag day).
key_role() { printf '%s|role:%s' "$CFG" "$DESK_ROLE" | shasum 2>/dev/null | cut -c1-16; }
sentinel_for() { # <prefix> <cwd> → path to USE (role-keyed for a role-holder, else legacy cwd-keyed)
  local pfx="$1" cwd="$2" rp cp
  cp="$STATE_DIR/$pfx-$(key_cwd "$cwd")"
  is_monitoring_desk || { printf '%s' "$cp"; return; }
  rp="$STATE_DIR/$pfx-$(key_role)"
  [ -f "$rp" ] && { printf '%s' "$rp"; return; }   # already migrated
  [ -f "$cp" ] && { printf '%s' "$cp"; return; }   # legacy opt-in still honored — never silently dropped
  printf '%s' "$rp"                                 # nothing yet → new state is role-keyed
}
arm_for()      { sentinel_for arm      "$1"; }
cooldown_for() { sentinel_for cooldown "$1"; }
cap_for()      { printf '%s/cap-%s'      "$STATE_DIR" "$1"; }               # keyed by session_id
# Stage-2 deterministic-fire state (Fable panel 2026-07-19):
escalate_for() { printf '%s/escalate-%s' "$STATE_DIR" "$1"; }              # SID-keyed: first-advisory time (grace clock)
fired_for()    { printf '%s/fired-%s'    "$STATE_DIR" "$1"; }              # SID-keyed: one-fire-per-SID latch (Stage-2 bound)
live_for()     { sentinel_for live      "$1"; } # cwd-keyed: live-fire opt-in (else SHADOW/log-only)
brief_for()    { sentinel_for brief     "$1"; } # cwd-keyed: standing successor-brief template
disarm_for()   { sentinel_for disarm    "$1"; } # cwd-keyed: per-desk opt-out (suppresses arm-by-default, G-P11-7)
escalated_for(){ printf '%s/escalated-%s' "$STATE_DIR" "$1"; }             # SID-keyed: T-P1-8 wedge page-once pacer
# Tiered-refresh state (4ce6ffc0194f, 2026-07-19):
idlewatch_for(){ printf '%s/idlewatch-%s' "$STATE_DIR" "$1"; }             # SID-keyed: first sub-T_IDLE fresh poll (adaptive-decay clock)
queued_for()   { printf '%s/queued-%s'    "$STATE_DIR" "$1"; }             # SID-keyed: Tier-2 refresh-queued marker (busy@medium wants a refresh)
busyforce_for(){ sentinel_for busyforce "$1"; } # cwd-keyed: Tier-3 forced-recycle EXEC opt-in (beyond --live; default OFF ⇒ shadow+page)
# Context-econ state (2026-07-20):
nudged_for()   { printf '%s/nudged-%s'    "$STATE_DIR" "$1"; }             # SID-keyed: busy pause-point-nudge pacer (fill at last nudge; re-arm per +NUDGE_REARM)
# Size-axis state (2026-07-29, K02 — header §9). Its OWN pacer, deliberately NOT escalated_for: sharing
# that stamp would let an RSS page suppress a wedge/busy page (or the reverse) — two distinct alarms
# silencing each other is the suppression trap, so each keeps its own window.
rsspaged_for() { printf '%s/rsspaged-%s'  "$STATE_DIR" "$1"; }             # SID-keyed: RSS-only page-once pacer (ESCALATE_DEDUP_S)

GRACE_S="${CC_WR_GRACE_S:-180}"                            # Stage-1 advisory → Stage-2 fire grace
# actuator (test seam): resolve next to this hook (repo hooks/../scripts + symlinked ~/.claude install)
_wrd="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
HANDOFF_FIRE="${CC_WR_HANDOFF_FIRE:-$_wrd/../scripts/handoff-fire.sh}"
[ -f "$HANDOFF_FIRE" ] || HANDOFF_FIRE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/handoff-fire.sh"

# context-econ signal lib (burn/forecast + interactive-recency, header §8) — same repo→install
# resolution as HANDOFF_FIRE; a MISSING lib degrades every signal seam to legacy behavior via the
# command -v guards at the call sites (a signal must never cost the hook).
_welib="$_wrd/lib/context-econ.sh"
[ -f "$_welib" ] || _welib="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/context-econ.sh"
# shellcheck source=lib/context-econ.sh
# shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
[ -f "$_welib" ] && . "$_welib" 2>/dev/null || true

# ---- Agent/operator CLI mode ---------------------------------------------------------------------
case "${1:-}" in
  arm)
    mkdir -p "$STATE_DIR" 2>/dev/null
    shift; _brief="" _live=0 _busyforce=0
    while [ $# -gt 0 ]; do case "$1" in
      --brief)      _brief="${2:?--brief needs a file}"; shift 2 ;;
      --live)       _live=1; shift ;;
      --busy-force) _busyforce=1; shift ;;
      *) echo "!! unknown arm arg: $1 (use: arm [--brief <file>] [--live] [--busy-force])" >&2; exit 2 ;;
    esac; done
    f="$(arm_for "$PWD")"; was_armed=0; [ -f "$f" ] && was_armed=1
    # ── FAIL-ATOMIC VALIDATION (durability, 2026-07-20) ────────────────────────────────────────────
    # Every refusal condition is checked BEFORE any marker is written, so a REFUSED arm changes
    # NOTHING on disk. The prior order wrote the arm sentinel first and only THEN refused `--live`
    # for a missing brief — exit 2, but the desk was left HALF-ARMED: `arm-<key>` present with
    # `live-<key>`/`brief-<key>` absent, i.e. armed-and-SHADOW *forever*. That state reads as "armed"
    # to `status` and to the hook's own opt-in gate, yet Stage 2 can never exec. Observed live under
    # .claude-quaternary (arm- written 01:03, no live-/brief-) — the desk polled for hours, passed the
    # arm gate, and shadow-logged instead of recycling. A half-success is the worst outcome for a
    # go-live actuator: it looks armed and is inert. Refuse whole, or apply whole.
    if [ -n "$_brief" ]; then
      { [ -f "$_brief" ] && [ -s "$_brief" ]; } || { echo "!! --brief file missing/empty: $_brief" >&2; exit 2; }
    fi
    if [ "$_live" = 1 ]; then
      # A usable brief must come from THIS invocation or from a prior arm of this cwd — checked here,
      # against the not-yet-written state, so the refusal leaves the previous state intact.
      { [ -n "$_brief" ] || [ -s "$(brief_for "$PWD")" ]; } || { echo "!! --live requires a non-empty --brief template first (no empty-payload fire)" >&2; exit 2; }
    fi
    # --busy-force: opt IN to the Tier-3 mid-work forced-recycle EXEC (beyond --live — a mid-work recycle is
    # riskier than an idle one). Without it, a busy+high desk still shadow-composes the drained brief + PAGES,
    # but does not exec. Requires --live (the busy exec gates on BOTH live + busyforce).
    if [ "$_busyforce" = 1 ]; then
      [ "$_live" = 1 ] || { echo "!! --busy-force requires --live (a mid-work forced recycle is opt-in beyond --live)" >&2; exit 2; }
    fi
    # ── all refusals cleared — every write below is unconditional ──────────────────────────────────
    rm -f "$(disarm_for "$PWD")" 2>/dev/null                # an explicit arm overrides a prior `clear` opt-out
    printf '%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ) $PWD" > "$f"
    # brief template = the Stage-2 successor prompt seed; hard-required for LIVE (no empty-payload fire, FM-D)
    [ -n "$_brief" ] && cp "$_brief" "$(brief_for "$PWD")" 2>/dev/null
    if [ "$_live" = 1 ]; then
      : > "$(live_for "$PWD")"; mode="LIVE (deterministic recycle EXECS handoff-fire --recycle)"
    else
      rm -f "$(live_for "$PWD")" 2>/dev/null; mode="SHADOW (deterministic recycle LOGS would-fire, does NOT exec)"
    fi
    if [ "$_busyforce" = 1 ]; then
      : > "$(busyforce_for "$PWD")"; mode="$mode + BUSY-FORCE (busy+high mid-work recycle ALSO execs)"
    else
      rm -f "$(busyforce_for "$PWD")" 2>/dev/null
    fi
    # A fresh opt-in clears a stale cooldown; a RE-ARM of an already-armed desk does NOT — re-arming
    # would clear the cross-generation loop-breaker (panel landmine). Arm survives the in-place recycle,
    # so a SUCCESSOR must NEVER re-arm.
    [ "$was_armed" = 0 ] && rm -f "$(cooldown_for "$PWD")" 2>/dev/null
    echo "armed $mode → $f"; exit 0 ;;
  clear)
    rm -f "$(arm_for "$PWD")" "$(cooldown_for "$PWD")" "$(live_for "$PWD")" "$(brief_for "$PWD")" "$(busyforce_for "$PWD")" 2>/dev/null
    # Durable disarm marker — the per-desk kill-switch must ALSO suppress arm-by-default (a desk that
    # still HOLDS the monitoring-desk role would otherwise re-arm on the next poll). `arm` removes it.
    mkdir -p "$STATE_DIR" 2>/dev/null; date -u +%Y-%m-%dT%H:%M:%SZ > "$(disarm_for "$PWD")" 2>/dev/null
    echo "cleared (this desk opted out of monitoring auto-recycle; disarm marker set — run 'arm' to re-enable)"; exit 0 ;;
  status)
    a="$(arm_for "$PWD")"; c="$(cooldown_for "$PWD")"
    if [ -f "$KILL" ]; then echo "GLOBAL KILL active ($KILL) — no session recycles"; fi
    if [ -f "$(disarm_for "$PWD")" ]; then echo "DISARMED (this cwd) — 'clear' opt-out suppresses arm-by-default; run 'arm' to re-enable"; fi
    echo "thresholds: idle≥${T_IDLE}% (adaptive → floor ${T_IDLE_FLOOR}% over ${IDLE_DECAY_S}s idle) · busy-force≥${T_BUSY}% · rot-floor ${ROT_FLOOR}%"
    echo "context-econ: conv-hold ${CONV_HOLD_S}s · nudge≥${T_NUDGE}% (re-arm +${NUDGE_REARM}%) · early-busy≥${T_BUSY_MIN}% @ forecast≤${LEAD_MIN}min"
    echo "size axis:    transcript≥${SIZE_MB}MB ⇒ full trigger (may recycle) · RSS≥${RSS_PAGE_MB}MB ⇒ PAGE ONLY (never auto-recycles; 0 disables either)"
    if [ -f "$a" ]; then
      echo "ARMED: $(cat "$a")"
      [ -f "$(live_for "$PWD")" ] && echo "  mode: LIVE (Stage-2 execs)" || echo "  mode: SHADOW (Stage-2 logs would-fire only)"
      [ -f "$(busyforce_for "$PWD")" ] && echo "  busy-force: ON (busy+high mid-work recycle also execs)" || echo "  busy-force: off (busy+high shadow-composes + pages, does NOT exec)"
      [ -s "$(brief_for "$PWD")" ] && echo "  brief: $(brief_for "$PWD") ($(wc -l < "$(brief_for "$PWD")" | tr -d ' ') lines)" || echo "  brief: none (LIVE blocked until set)"
    else echo "not armed by sentinel (this cwd) — a session HOLDING the '$DESK_ROLE' role is armed-by-default at poll time (SHADOW) unless disarmed"; fi
    if [ -f "$c" ]; then
      cd_at="$(cat "$c" 2>/dev/null || echo 0)"; left=$(( COOLDOWN_S - ( $(date +%s) - ${cd_at:-0} ) ))
      [ "$left" -gt 0 ] 2>/dev/null && echo "cooldown: ${left}s remaining" || echo "cooldown: expired"
    fi
    exit 0 ;;
  kill)   mkdir -p "$STATE_DIR" 2>/dev/null; date -u +%Y-%m-%dT%H:%M:%SZ > "$KILL"; echo "GLOBAL KILL set → $KILL"; exit 0 ;;
  unkill) rm -f "$KILL" 2>/dev/null; echo "global kill removed"; exit 0 ;;
esac

# ---- PostToolUse actuation mode (no recognized arg; JSON on stdin) --------------------------------
input="$(cat 2>/dev/null || printf '{}')"

# ── B-3: one IDL line per invocation (fired|abstained). "didn't fire" ≠ "never evaluated". ──
# SIZE_JSON (header §9) — the measured size pair, merged into every record once 4a-quater has run.
# Empty until then, so the pre-measurement abstains (no-jq / not-armed / cooldown …) stay unchanged
# rather than claiming a measurement that never happened. The merge happens inside log_idl (via
# idl_init's merge-var slot), so every record carries the pair by CONSTRUCTION rather than by
# remembering to pass it at ~12 call sites.
SIZE_JSON='{}'
# Writer body = the SSOT lib hooks/lib/idl-log.sh (consolidation audit 02); see that file for the
# "jq-encode EVERY field" invariant this used to duplicate in four places.
_ilib="$_wrd/lib/idl-log.sh"
# A BRAND-NEW hooks/lib file has no ~/.claude/hooks/lib symlink until install.sh runs — and when
# this hook executes from ~/.claude/hooks/, the CFG and $HOME tiers below resolve to that SAME
# missing path. So resolve $0's own symlink into the checkout first: the live hook IS a symlink to
# the repo, so this finds the lib on the same fast-forward that delivers this hook. Without it,
# landing would leave all five IDL hooks inert until someone remembered to re-run install.sh.
[ -f "$_ilib" ] || { _itgt="$0"; [ -L "$_itgt" ] && _itgt="$(readlink "$_itgt")"
  _ilib="$(cd "$(dirname "$_itgt")" 2>/dev/null && pwd)/lib/idl-log.sh"; }
[ -f "$_ilib" ] || _ilib="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/idl-log.sh"
[ -f "$_ilib" ] || _ilib="$HOME/.claude/hooks/lib/idl-log.sh"
# shellcheck source=lib/idl-log.sh
# shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
if ! . "$_ilib" 2>/dev/null; then
  # Fail LOUD but SAFE — a hook that cannot log its own disposition must not proceed silently, and
  # must never block the turn on a misconfig.
  printf 'waiting-recycle: FATAL — cannot source %s (IDL writer inert).\n' "$_ilib" >&2
  exit 0
fi
idl_init "$IDL" "waiting-recycle" "SID" "SIZE_JSON"

# T-P1-8 out-of-band operator pages (API-independent; BOTH are safe no-ops when unavailable/unarmed).
wr_os_notify() { # $1=title $2=msg — OS notification (osascript, or a stub in tests via CC_WR_NOTIFY)
  if [ -n "$NOTIFY_CMD" ]; then "$NOTIFY_CMD" "$1" "$2" >/dev/null 2>&1 || true; return 0; fi
  command -v osascript >/dev/null 2>&1 && \
    wrc_osa osascript -e "display notification \"${2//\"/}\" with title \"${1//\"/}\"" >/dev/null 2>&1 || true
}
wr_push_page() { # $1=msg — Pushover break-through; no-op (return 0) when the hook is missing/INERT
  [ -x "$PUSH_BIN" ] || return 0
  jq -cn --arg m "$1" --arg c "$CWD" '{message:$m,cwd:$c}' | "$PUSH_BIN" >/dev/null 2>&1 || true
}

# ── BATS-POLLUTION GC ─────────────────────────────────────────────────────────────────────────────
# waiting-recycle's own bats suite keys arm markers by a fixture cwd. A run that forgot to override
# CC_WR_STATE_DIR — or a helper that armed under the REAL config root — leaves arm/live/brief markers in
# the REAL state dir whose recorded cwd is a defunct /var/folders/…bats-run tmpdir; that litter also
# reads as "armed" to `status`. Sweep it: an arm marker whose recorded cwd has the bats-run tmpdir shape
# AND no longer exists on disk is test pollution. A LIVE bats run's own fixture cwd STILL EXISTS, so the
# existence gate makes this safe to run every poll — it never touches an in-flight run's own markers.
gc_bats_pollution() {
  [ -d "$STATE_DIR" ] || return 0
  local f firstline cwd hash sib
  for f in "$STATE_DIR"/arm-*; do
    [ -f "$f" ] || continue
    IFS= read -r firstline < "$f" 2>/dev/null || continue      # arm content line 1: "<iso-ts> <cwd>"
    cwd="${firstline#* }"                                        # drop the ts token → the recorded cwd
    case "$cwd" in
      /var/folders/*bats-run*|/private/var/folders/*bats-run*) ;;
      *) continue ;;
    esac
    [ -d "$cwd" ] && continue                                   # a LIVE test's fixture cwd still exists ⇒ keep
    hash="${f##*/arm-}"                                          # sweep the whole cwd-keyed family for this key
    for sib in arm live brief cooldown disarm busyforce; do rm -f "$STATE_DIR/$sib-$hash" 2>/dev/null; done
    log_idl gc "bats-pollution" "$(jq -cn --arg cwd "$cwd" --arg key "$hash" '{gc:"arm-family",cwd:$cwd,key:$key}')"
  done
}

command -v jq >/dev/null 2>&1 || { SID="?"; abstain "no-jq"; }

SID="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"
TP="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
CWD="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
CMD="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"

[ -n "$SID" ] || abstain "no-session-id"

# Housekeeping (cheap, every poll): sweep bats-run pollution markers so a forgotten CC_WR_STATE_DIR
# override in a test can never leave the REAL state dir armed by a defunct fixture cwd. Existence-gated,
# so an in-flight bats run's own markers survive. Runs even under global-kill (pure hygiene).
gc_bats_pollution

# 2. GLOBAL kill-switch — blanket opt-out for every session.
[ -f "$KILL" ] && abstain "global-kill"

# cwd is needed for the arm / cooldown / clean-tree checks — no cwd, nothing to reason about.
{ [ -n "$CWD" ] && [ -d "$CWD" ]; } || abstain "no-cwd"

# 1. OPT-IN (ARM-BY-DEFAULT, G-P11-7): a builder is never touched, but a MONITORING DESK is armed
# without the manual `arm` step. A per-desk `clear` disarm marker suppresses BOTH the sentinel and the
# role-arm (the kill-switch must still bite a role-holding desk). LIVE exec stays gated on live_for, so
# a role-armed desk is SHADOW by default (damp-first).
[ -f "$(disarm_for "$CWD")" ] && abstain "disarmed"
armed_by=""
if   [ -f "$(arm_for "$CWD")" ]; then armed_by="sentinel"
elif is_monitoring_desk;        then armed_by="desk-role"
fi
[ -n "$armed_by" ] || abstain "not-armed"

# GUARD: never advise-recycle off the recycle/handoff machinery's OWN Bash calls (defense-in-depth;
# the cooldown set at fire-time also covers this, but an explicit guard removes any ordering risk).
case "$CMD" in
  *handoff-fire*|*/handoff*|*waiting-recycle*|*"self-close"*) abstain "recycle-machinery" ;;
esac

# 3. COOLDOWN (cwd-keyed) + 6. CAP (SID-keyed) pace the ADVISORY (Stage 1) ONLY. The deterministic
# FIRE (Stage 2) is EXEMPT from both: it must escalate after grace even though the first advisory
# stamped the cooldown, and a non-exempt Stage 2 would be permanently silenced after MAX ignored
# advisories (the panel's cap-trap). So compute them as FLAGS; apply them only on the Stage-1 branch.
cf="$(cooldown_for "$CWD")"; cooled=0
if [ -f "$cf" ]; then
  cd_at="$(cat "$cf" 2>/dev/null || echo 0)"; case "$cd_at" in ''|*[!0-9]*) cd_at=0 ;; esac
  [ "$(( $(date +%s) - cd_at ))" -lt "$COOLDOWN_S" ] && cooled=1
fi
capf="$(cap_for "$SID")"
N="$(cat "$capf" 2>/dev/null || echo 0)"; case "$N" in ''|*[!0-9]*) N=0 ;; esac
capped=0; [ "$N" -ge "$MAX" ] && capped=1

# Stage-2 PENDING? (cheap; decides whether the expensive trigger+SAFE eval must run even when
# cooled/capped): a prior advisory left an escalate stamp, grace has elapsed, and this SID has not
# yet fired.
escf="$(escalate_for "$SID")"; firedf="$(fired_for "$SID")"; stage2_pending=0
if [ -f "$escf" ] && [ ! -f "$firedf" ]; then
  est="$(cat "$escf" 2>/dev/null)"; case "$est" in ''|*[!0-9]*) est=0 ;; esac
  [ "$est" -gt 0 ] && [ "$(( $(date +%s) - est ))" -ge "$GRACE_S" ] && stage2_pending=1
fi

# T-P1-8 WEDGE — a desk that has exhausted its recycle attempts but is STILL fire-worthy must ESCALATE
# (page) not silently ride to auto-compaction. Two wedge shapes: the advisory CAP is reached, or a
# SHADOW would-fire already latched (already-fired recurs ONLY in shadow — a LIVE fire recycles to a
# fresh SID). The cwd COOLDOWN gates it (a recent advisory/fire ⇒ not yet wedged), and its own page-once
# pacer (escalated_for + ESCALATE_DEDUP_S) throttles the ongoing pages. Detected as a FLAG here; the
# page happens only AFTER the trigger+SAFE eval below confirms the desk is genuinely fire-worthy-and-
# just-waiting (never page a mid-work/holding desk).
shadow_fired=0; { [ "$stage2_pending" = 0 ] && [ -f "$firedf" ]; } && shadow_fired=1
wedged=0; escalation_paced=0
if [ "$stage2_pending" = 0 ] && [ "$cooled" = 0 ]; then
  { [ "$capped" = 1 ] || [ "$shadow_fired" = 1 ]; } && wedged=1
fi
if [ "$wedged" = 1 ] && [ -f "$(escalated_for "$SID")" ]; then
  ed_at="$(cat "$(escalated_for "$SID")" 2>/dev/null || echo 0)"; case "$ed_at" in ''|*[!0-9]*) ed_at=0 ;; esac
  [ "$(( $(date +%s) - ed_at ))" -lt "$ESCALATE_DEDUP_S" ] && { wedged=0; escalation_paced=1; }
fi
# Fast-path abstains (preserve the pre-restructure perf + reasons) — but NOT when a wedge must escalate:
# a wedged desk falls through to the trigger+SAFE eval so the escalate branch can page it.
if [ "$stage2_pending" = 0 ] && [ "$wedged" = 0 ]; then
  [ "$escalation_paced" = 1 ] && abstain "escalation-paced"
  [ "$cooled" = 1 ] && abstain "cooldown"
  [ "$capped" = 1 ] && abstain "capped:${N}>=${MAX}"    # defensive backstop (unreachable unless cooled/paced cleared the wedge)
fi

# 4a. Context fill (telemetry) — fresh number only; an old % is not evidence of the current fill.
used=0; fresh=0
tel="$TEL_DIR/$SID.json"
if [ -f "$tel" ]; then
  ts="$(jq -r '.ts // 0' "$tel" 2>/dev/null || echo 0)"; ts="${ts%.*}"; case "$ts" in ''|*[!0-9]*) ts=0 ;; esac
  age=$(( $(date +%s) - ts ))
  if [ "$age" -le "$AGE_MAX" ]; then
    fresh=1
    used="$(jq -r '.used_pct // 0' "$tel" 2>/dev/null || echo 0)"; used="${used%.*}"
    case "$used" in ''|*[!0-9]*) used=0 ;; esac
  fi
fi
# 4a-ter. CONTEXT-ECON velocity (header §8): sample this poll into the burn history, then read the
# velocity + minutes-to-wall forecast. Lib missing / data sparse ⇒ burn 0 + forecast -1 = the exact
# legacy behavior at every consumer below.
burn_x100=0; forecast_min=-1
if command -v ce_sample >/dev/null 2>&1 && [ -f "$tel" ]; then
  ce_sample "$tel" || true
  _bf="$(ce_burn "$tel" 2>/dev/null || printf '0 -1')"
  burn_x100="${_bf%% *}"; forecast_min="${_bf##* }"
  case "$burn_x100" in ''|*[!0-9]*) burn_x100=0 ;; esac
  case "$forecast_min" in -1) ;; ''|*[!0-9]*) forecast_min=-1 ;; esac
fi
# 4a-bis. ADAPTIVE IDLE THRESHOLD (4ce6ffc0194f): the base T_IDLE decays toward T_IDLE_FLOOR the longer
# this SID has sat below it on fresh polls — a desk idle for hours grows more eager to shed watch-rot
# (the "sat idle for hours then hit 74%" evidence). The clock is stamped on the FIRST sub-T_IDLE fresh
# poll and rides the SID; a recycle mints a fresh SID (clock resets) and the cwd cooldown still gates
# churn, so the decay cannot spin. IDLE_DECAY_S=0 disables it (eff_idle == T_IDLE). The decay lowers ONLY
# the IDLE bar; the BUSY forced path keys on T_BUSY, never eff_idle.
eff_idle="$T_IDLE"
if [ "$fresh" = 1 ]; then
  iwf="$(idlewatch_for "$SID")"
  { [ "$used" -lt "$T_IDLE" ] && [ ! -f "$iwf" ]; } && { date +%s > "$iwf" 2>/dev/null || true; }
  if [ -f "$iwf" ] && [ "$IDLE_DECAY_S" -gt 0 ] 2>/dev/null; then
    iw="$(cat "$iwf" 2>/dev/null || echo 0)"; case "$iw" in ''|*[!0-9]*) iw=0 ;; esac
    if [ "$iw" -gt 0 ]; then
      idle_age=$(( $(date +%s) - iw )); [ "$idle_age" -lt 0 ] && idle_age=0
      span=$(( T_IDLE - T_IDLE_FLOOR )); [ "$span" -lt 0 ] && span=0
      drop=$(( span * idle_age / IDLE_DECAY_S )); [ "$drop" -gt "$span" ] && drop="$span"
      eff_idle=$(( T_IDLE - drop )); [ "$eff_idle" -lt "$T_IDLE_FLOOR" ] && eff_idle="$T_IDLE_FLOOR"
    fi
  fi
fi
over_threshold=0; { [ "$fresh" = 1 ] && [ "$used" -ge "$eff_idle" ]; } && over_threshold=1

# 4a-quater. SIZE AXIS (header §9) — the one signal that does NOT reset on compaction. Deliberately NOT
# gated on telemetry freshness like used_pct is: transcript bytes are read from the file THIS invocation,
# so they are self-fresh, and RSS comes from a live `ps` — a stale telemetry file only costs us the pid
# (⇒ rss_mb 0 = unknown). That is why a size trigger still works on exactly the sessions whose
# telemetry writer has died, where every used_pct path is already blind.
tx_mb=0; rss_mb=0
if command -v ce_size >/dev/null 2>&1; then
  _sz="$(ce_size "$TP" "$tel" 2>/dev/null || printf '0 0')"
  tx_b="${_sz%% *}"; rss_kb="${_sz##* }"
  case "$tx_b"   in ''|*[!0-9]*) tx_b=0 ;;   esac
  case "$rss_kb" in ''|*[!0-9]*) rss_kb=0 ;; esac
  tx_mb=$(( tx_b / 1048576 )); rss_mb=$(( rss_kb / 1024 ))
fi
# Threshold 0 disables the axis; an unknown (0) measurement can never clear a positive threshold, so
# both gates fail-safe to the pre-size behavior (false-negative bias, the house rule).
over_size=0; { [ "$SIZE_MB" -gt 0 ] 2>/dev/null && [ "$tx_mb" -ge "$SIZE_MB" ]; } && over_size=1
rss_over=0; { [ "$RSS_PAGE_MB" -gt 0 ] 2>/dev/null && [ "$rss_mb" -ge "$RSS_PAGE_MB" ]; } && rss_over=1
# Publish the measured pair into SIZE_JSON — log_idl merges it into EVERY record from here on, fired or
# abstained. Structural, not per-call-site: a dormant threshold must never be indistinguishable from
# broken wiring, and this is the data the operator calibrates the thresholds DOWN from (header §9).
# VALIDATE before publishing: log_idl feeds this to `jq --argjson`, so a malformed value would fail the
# WHOLE record and silently drop every IDL line from here on — the same "reads as no records ⇒ alarm
# flips GREEN" trap log_idl's own comment guards against, one level up. Fall back to {} on any doubt.
_sj="$(jq -cn --argjson tx "$tx_mb" --argjson rss "$rss_mb" --argjson st "$SIZE_MB" --argjson rt "$RSS_PAGE_MB" \
  '{tx_mb:$tx,rss_mb:$rss,size_mb_t:$st,rss_page_t:$rt}' 2>/dev/null || true)"
# shellcheck disable=SC2034  # consumed by indirection in hooks/lib/idl-log.sh (idl_init merge-var slot)
if [ -n "$_sj" ] && printf '%s' "$_sj" | jq -e 'type=="object"' >/dev/null 2>&1; then SIZE_JSON="$_sj"; else SIZE_JSON='{}'; fi

# ── BOUNDED TRANSCRIPT READS (M13, docs/plans/MACHINE_CAPACITY_V2.md §11) ────────────────────────
# This hook fires on EVERY PostToolUse — ~19× the Stop chain's rate — and BOTH reads below walked the
# whole transcript, which reaches 3-5 MB. Measured on a 5.5 MB fixture: 438ms/call for the full `jq`
# pass vs 24ms bounded (18×), i.e. the READ dominated the hook. Both are now bounded to the LAST
# CC_WR_TAIL_BYTES of the file. SEMANTICS CONTRACT: each pipeline needs the FINAL record(s) of a
# JSONL transcript by construction, so the answer is identical whenever they sit inside the window —
# and where the window could MISS them, each read falls back to the unbounded incumbent (correctness
# over cost, the house rule). CC_WR_TAIL_BYTES=0 — or set-but-EMPTY, or non-numeric — restores the
# incumbent unbounded reach verbatim.
if [ -n "${CC_WR_TAIL_BYTES+set}" ]; then TAIL_B="$CC_WR_TAIL_BYTES"; else TAIL_B=262144; fi
case "$TAIL_B" in ''|*[!0-9]*) TAIL_B=0 ;; esac   # unreadable seam ⇒ 0 ⇒ full read (fail-safe to correctness)

# 4b. Behavioral ROT tell — the desk re-deriving already-known orchestration state (confusion /
# memory-loss markers a HEALTHY polling desk does not emit; NOT generic "let me check X"). Fires
# even below threshold. Read the LAST assistant text block (streaming tail — never slurp a big
# transcript). Corpus-validated in tests/waiting-recycle.bats.
#
# `fromjson? | objects` is LOAD-BEARING, not cosmetic: the first line of a tail window is usually a
# PARTIAL record, and plain `jq -c` ABORTS THE WHOLE STREAM on it (verified — one parse error, ZERO
# records emitted), so a naive `tail | jq -c` would silently blank MSG and take the entire rot axis
# dark. -R + fromjson? drops the partial line and keeps the rest; it is also the idiom the sibling
# transcript readers in hooks/lib/context-econ.sh already use. It can only find MORE records than the
# incumbent (a lone corrupt/scalar line no longer kills the pass), never fewer — the safe direction.
# ONE program text, applied identically to the window and to the fallback, so the two cannot drift.
WR_ASST='fromjson? | objects | select(.type=="assistant") | tojson'
rot=0; MSG=""
if [ -n "$TP" ]; then
  case "$TP" in "~"*) TP="$HOME${TP#\~}" ;; esac
  if [ -f "$TP" ]; then
    _asst=""
    if [ "$TAIL_B" -gt 0 ]; then
      _asst="$(tail -c "$TAIL_B" "$TP" 2>/dev/null | jq -Rr "$WR_ASST" 2>/dev/null | tail -1 || true)"
      # NO RECORD IN THE WINDOW is the ONLY miss that warrants the full read — and only when the file
      # is actually bigger than the window (else the window WAS the file). A record found but whose
      # text blocks join to "" is a FACT (a tool-use-only turn, common for a polling desk); re-reading
      # 5 MB every poll to re-learn that fact would forfeit the whole optimization. Same escalation
      # shape as ce_last_interactive_age's own tail-miss fallback.
      if [ -z "$_asst" ]; then
        _fsz="$(wc -c < "$TP" 2>/dev/null | tr -d ' ')"; case "$_fsz" in ''|*[!0-9]*) _fsz=0 ;; esac
        [ "$_fsz" -gt "$TAIL_B" ] && _asst="$(jq -Rr "$WR_ASST" "$TP" 2>/dev/null | tail -1 || true)"
      fi
    else
      _asst="$(jq -Rr "$WR_ASST" "$TP" 2>/dev/null | tail -1 || true)"
    fi
    [ -n "$_asst" ] && MSG="$(printf '%s' "$_asst" \
      | jq -r '[.message.content[]? | select(.type=="text") | .text] | join("\n")' 2>/dev/null || true)"
  fi
fi
# CONTEXT-ECON interactive recency (header §8, S6): age of the last operator/peer turn, or "" when
# none is visible (auto-drive re-prompts and tool traffic excluded by the lib — see its taxonomy).
# BOUNDED (M13): the lib is already tail-bounded, but at its OWN 2 MB default — 8× this window. We hand
# it CC_WR_TAIL_BYTES through its documented CC_CE_TAIL_BYTES seam rather than touching the lib. The
# ANSWER is window-INDEPENDENT: on a tail-miss over a bigger file the lib re-scans the WHOLE file with
# the identical program (and ce_transcript_visible escalates the same way), so an operator turn buried
# before the window still HOLDS — pinned by tests/waiting-recycle-bounded-read.bats. Cost: strictly
# cheaper for the 2 MB+ transcripts this targets; worst case (a miss on a file between the two windows)
# is ONE extra window-sized probe. An explicit CC_CE_TAIL_BYTES is the MORE SPECIFIC seam and wins.
conv_age=""
if command -v ce_last_interactive_age >/dev/null 2>&1 && [ -n "$TP" ] && [ -f "$TP" ]; then
  if [ "$TAIL_B" -gt 0 ] && [ -z "${CC_CE_TAIL_BYTES:-}" ]; then
    conv_age="$(CC_CE_TAIL_BYTES="$TAIL_B" ce_last_interactive_age "$TP")"
  else
    conv_age="$(ce_last_interactive_age "$TP")"
  fi
  case "$conv_age" in *[!0-9]*) conv_age="" ;; esac
fi
# Bound grep input (a re-derivation tell is opening narration; this is a hang-safety backstop, not
# a correctness limit). Combined with the backtracking-SAFE regex below (≤1 bounded gap per branch,
# NO overlapping quantifiers — an earlier `[a-z]*[^.]{0,40}` form ReDoS-hung on near-miss inputs).
MSG="${MSG:0:4000}"
ROT_TELLS='(lost|losing) track|(remind|reorient|reacquaint) (myself|me)|(do(n.?t| not)|no longer|can.?t|cannot) (recall|remember)|(not sure|not certain|no longer sure|unsure)( any ?more|,? (which|what|where|how many|whether))|what was i (monitoring|watching|waiting|tracking|doing|supposed)|which (sessions?|ones?|teammates?|tasks?)[^.]{0,20}(did i|was i|were we|had i|do i)|(did|do) i (fire|launch|spawn|start|kick|have)[^.]{0,20}(again|already|so far)|(reconstruct|re-?establish|re-?derive|re-?orient|re-?build|re-?assemble)[^.]{0,15}(state|context|picture|status|situation|standing|where|what|which)|re-?(check|read|verify|confirm|examine|scan)[^.]{0,15}(which|what|the current|whether|where things|from scratch)|from scratch|starting over|(again|already),? (which|what|how many|who|whether)|(which|what|how many)[^.]{0,25}(again|already|so far)'
[ -n "$MSG" ] && printf '%s' "$MSG" | grep -iqE "$ROT_TELLS" && rot=1

# 4. TRIGGER gate — threshold OR FLOORED behavioral rot. A rot-tell needs FRESH telemetry AND
# used_pct ≥ ROT_FLOOR to count: rot physically requires accumulated context, and the shipped regex
# matches HEALTHY watch narration ("re-checking which sessions are still running") — an un-floored
# rot-tell at single-digit fill is by construction re-orientation narration, not rot (probe P1,
# 2026-07-19: the regex trips on 3/5 benign monitoring lines). The floor also closes the
# cross-generation rot-tell recycle-storm (a fresh successor's re-orientation narration can't re-fire
# below the floor). fresh=0 (telemetry writer dead) ⇒ rot cannot fire — FM-G is covered by a separate
# stale-telemetry alarm, not by firing blind on a lagging tell.
rot_valid=0; { [ "$rot" = 1 ] && [ "$fresh" = 1 ] && [ "$used" -ge "$ROT_FLOOR" ]; } && rot_valid=1

# ── 4c. RSS-ONLY PAGE (header §9) — MUST sit ABOVE the trigger-gate abstain below. That abstain is the
# barrier a3 identified: the entire apparatus (advisory, Stage 2, wedge page, busy page) lives downstream
# of it, so a size-dangerous session at low fill exited before reaching even an operator page. RSS is
# page-only and fires ONLY as the SOLE signal — any other trigger falls through to the ladder, which has
# an actual lever (a recycle) where RSS alone has only a guess. Paging is fleet-safe, so this ships LIVE
# (same rule as the wedge/busy pages); its own SID-keyed pacer bounds the repeat.
if [ "$rss_over" = 1 ] && [ "$over_threshold" = 0 ] && [ "$rot_valid" = 0 ] && [ "$over_size" = 0 ]; then
  rpf="$(rsspaged_for "$SID")"; rp_send=1
  if [ -f "$rpf" ]; then
    rp_at="$(cat "$rpf" 2>/dev/null || echo 0)"; case "$rp_at" in ''|*[!0-9]*) rp_at=0 ;; esac
    [ "$(( $(date +%s) - rp_at ))" -lt "$ESCALATE_DEDUP_S" ] && rp_send=0
  fi
  if [ "$rp_send" = 1 ]; then
    mkdir -p "$STATE_DIR" 2>/dev/null || true
    date +%s > "$rpf" 2>/dev/null || true
    log_idl escalated "rss-only-page" "$(jq -cn --argjson used "$used" '{used_pct:$used,rss_page:true,forceable:false}')"
    wr_os_notify "Claude session RSS high" "desk ${UUID:-$SID} RSS ${rss_mb}MB ≥ ${RSS_PAGE_MB}MB at only ${used}% context"
    wr_push_page "HIGH-RSS SESSION (${DESK_ROLE}) ${rss_mb}MB RSS at ${used}% ctx / ${tx_mb}MB transcript — /handoff to reset the process"
    rmsg="⚠ HIGH PROCESS FOOTPRINT — this session's process is at ${rss_mb}MB RSS (≥ ${RSS_PAGE_MB}MB) while context is only ${used}% and its transcript ${tx_mb}MB. Context fill will NOT warn you about this: RSS is a near-independent axis (measured pearson +0.26 vs transcript bytes), and only a NEW PROCESS resets it — /compact does not. Nothing is auto-recycled on RSS alone (the dangerous level is unproven, so forcing the fleet on it would be a guess): this is a page. If you are at a clean boundary, run /handoff to recycle into a fresh process. Re-pages every ${ESCALATE_DEDUP_S}s. Kill-switch: \`waiting-recycle.sh clear\`."
    jq -nc --arg a "$rmsg" --arg s "$rmsg" \
      '{decision:"block",reason:$s,systemMessage:$s,hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$a}}'
    exit 0
  fi
  abstain "rss-page-paced:${rss_mb}MB"
fi

{ [ "$over_threshold" = 1 ] || [ "$rot_valid" = 1 ] || [ "$over_size" = 1 ]; } || abstain "below-threshold-no-tell:used=${used},fresh=${fresh},rot=${rot},floor=${ROT_FLOOR},tx=${tx_mb}MB,sizeT=${SIZE_MB}MB"

# 5. SAFE vs BUSY — we no longer abstain at the first hold: we CLASSIFY it and fall through to the
# decision-routing block (idle-fire vs busy-force vs busy-page vs Tier-2 hold). Every clause stays
# FALSE-NEGATIVE-safe (an unreadable/ambiguous signal HOLDS). First hold, in order, wins.
#   • class=soft — disk-DURABLE state (uncommitted tree, inbound wait-contract, mailbox ping): the
#     successor inherits it from disk, so at HIGH context the busy-force path recycles anyway and DRAINS
#     the pings into the successor brief (nothing dropped — the Tier-3 point).
#   • class=hard — would LOSE state or BURY a decision if recycled (git sequencer mid-merge, open operator
#     decision, live context-bound teammate): NEVER force — at high context it PAGES, it does not recycle.
SAFE=1; hold_class=""; hold_reason=""
hold() { if [ "$SAFE" = 1 ]; then SAFE=0; hold_class="$1"; hold_reason="$2"; fi; }

# 5a. Clean tree + no git SEQUENCER state. Dirty tree (SOFT): the working tree survives a pane recycle, so
# the successor inherits the uncommitted change (flagged in the brief). Live merge/rebase/cherry-pick
# (HARD): porcelain-CLEAN at step boundaries yet mid-active-work (the audit's "mid-merge between clean
# states", Fable panel S1) — fresh context mid-sequencer is error-prone, so page not force.
if [ "$SAFE" = 1 ] && git -C "$CWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  [ -z "$(git -C "$CWD" status --porcelain 2>/dev/null)" ] || hold soft "dirty-tree-hold"
  gd="$(git -C "$CWD" rev-parse --git-dir 2>/dev/null)"
  if [ "$SAFE" = 1 ] && [ -n "$gd" ]; then
    case "$gd" in /*) ;; *) gd="$CWD/$gd" ;; esac
    for seq in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply; do
      [ -e "$gd/$seq" ] && { hold hard "sequencer-state-hold:$seq"; break; }
    done
  fi
fi
# 5b. Open decision/blocker in the last message (reuse anti-deference's GENUINE carve-out): a desk
# waiting on the operator's call must SURFACE, not silently recycle the question away (HARD).
GENUINE='your (credential|password|api.?key|secret|token|login|cookie)|need (your|the)[^.]{0,40}(credential|password|secret|token|key|access|permission|approval)|only you (can|have|know)|(don.?t|do not|no) [a-z ]{0,20}access|which account|you.?ll need to (provide|give|share|tell|run|log ?in)|i (don.?t|do not) have (access|the |your |permission)|can you (provide|share|tell me|give me|confirm which)|which (do you|would you|of (these|the)|option|approach|one)|(would|do) you prefer|your call|up to you|how would you like|which direction|your approval|requires? (your|sudo|approval|authentication)|run (this|it|the [a-z ]{0,20}) ?yourself|sudo|interactive login|auth login|pushing to (main|origin)|push (is|remains)[^.]{0,20}your call|won.?t push|will not push|not push(ing)? (to|without)|force.?push|destructive migration|drop table|delete[^.]{0,20}production|navigation pattern|(db|database) timeout'
[ "$SAFE" = 1 ] && [ -n "$MSG" ] && printf '%s' "$MSG" | grep -iqE "$GENUINE" && hold hard "open-decision-hold"

# 5c. Active-COORDINATION (Fable panel 2026-07-19 S3/S4/S5). S5 live teammate = HARD. S3 inbound wait +
# S4 mailbox = SOFT (durable on disk; the busy-force path DRAINS them into the successor brief). The
# desk's OWN waiter-contracts do NOT hold (durable — the successor resumes them). COORD/UUID resolved above.
QUIET_S="${CC_WR_QUIET_S:-180}"                             # S4: a mailbox line fresher than this = active
now_s="$(date +%s)"
# identity set a peer addresses THIS desk by: session_id, pane uuid, or a role file resolving to either.
ident_is_me() { # $1=addressee → 0 if it names this desk
  local w="$1"; [ -n "$w" ] || return 1
  { [ "$w" = "$SID" ] || { [ -n "$UUID" ] && [ "$w" = "$UUID" ]; }; } && return 0
  if [ -f "$COORD/cc-roles/$w" ]; then
    local rv; rv="$(cat "$COORD/cc-roles/$w" 2>/dev/null)"
    { [ "$rv" = "$SID" ] || { [ -n "$UUID" ] && [ "$rv" = "$UUID" ]; }; } && return 0
  fi
  return 1
}
mbx_active() { # $1=mailbox file → 0 if touched within QUIET_S
  [ -f "$1" ] || return 1
  local mt; mt="$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0)"
  case "$mt" in ''|*[!0-9]*) mt=0 ;; esac
  [ "$(( now_s - mt ))" -lt "$QUIET_S" ]
}
# S5 — live context-bound TEAMMATES (HARD HOLD — teammate/TaskOutput results route to THIS SID; a recycle
# or /compact kills them unrecoverably). Signal: a team dir created BY this session (existence ⇒ HOLD).
if [ "$SAFE" = 1 ]; then
  for td in "$CFG"/teams/session-"${SID:0:8}"*; do
    { [ -d "$td" ] && [ -f "$td/config.json" ]; } && { hold hard "live-team-hold"; break; }
  done
fi
# S3 — a peer is contract-BLOCKED on this desk: OPEN wait-contract, waitee names me, deadline future,
# waiter still ALIVE (a dead waiter's OPEN contract is a zombie — kill -0 filters it, panel S3). SOFT.
if [ "$SAFE" = 1 ] && [ -d "$COORD/wait-contracts" ]; then
  for wc in "$COORD"/wait-contracts/*.json; do
    [ -f "$wc" ] || continue
    [ "$(jq -r '.status // empty' "$wc" 2>/dev/null)" = "OPEN" ] || continue
    ident_is_me "$(jq -r '.waitee // empty' "$wc" 2>/dev/null)" || continue
    dl="$(jq -r '.deadline // 0' "$wc" 2>/dev/null)"; case "$dl" in ''|*[!0-9]*) dl=0 ;; esac
    [ "$dl" -gt "$now_s" ] || continue                        # past deadline ⇒ not a live block
    wp="$(jq -r '.waiter_pid // empty' "$wc" 2>/dev/null)"
    { [ -n "$wp" ] && ! kill -0 "$wp" 2>/dev/null; } && continue   # dead waiter ⇒ zombie, skip
    hold soft "inbound-wait-hold"; break
  done
fi
# S4 — a peer just reached for this desk (mailbox line fresher than QUIET_S). cc-notify ALWAYS
# mailbox-writes before injecting, and cc-dispatch workers notify the desk ROLE without a contract, so S3
# alone under-detects — S4 is load-bearing. Check the own-uuid mailbox + any role resolving to me. SOFT.
if [ "$SAFE" = 1 ]; then
  { [ -n "$UUID" ] && mbx_active "$COORD/mailbox/$UUID.md"; } && hold soft "inbox-active-hold"
fi
if [ "$SAFE" = 1 ] && [ -d "$COORD/cc-roles" ]; then
  for rf in "$COORD"/cc-roles/*; do
    [ -f "$rf" ] || continue
    rv="$(cat "$rf" 2>/dev/null)"
    { [ "$rv" = "$SID" ] || { [ -n "$UUID" ] && [ "$rv" = "$UUID" ]; }; } || continue
    mbx_active "$COORD/mailbox/$rv.md" && { hold soft "inbox-active-hold-role"; break; }
  done
fi
# 5d — S6 CONVERSATION-VALUE hold (context-econ, header §8). A fresh INTERACTIVE turn (operator typed
# or a peer injected < CONV_HOLD_S ago) marks a live 2-way exchange — HIGH-VALUE context that leaves
# NO git/mailbox trace, which is exactly how the desk hit 74% MID-conversation while classified idle.
# SOFT: below the busy ceiling the recycle waits for the exchange to quiet; at/above it the forced
# drain still recycles (riding to the wall destroys the same exchange PLUS the session). The lib
# excludes auto-drive re-prompts on two axes, so an auto-driven desk still free-wins.
if [ "$SAFE" = 1 ] && [ -n "$conv_age" ] && [ "$conv_age" -lt "$CONV_HOLD_S" ] 2>/dev/null; then
  hold soft "operator-conversing-hold"
fi

# drain_scan — print the desk's PENDING ping queue (mailbox tails + inbound OPEN contracts naming me), or
# nothing. Tier-3 busy-force embeds this in the successor brief so a mid-work recycle drops NO ping. It
# carries ALL pending content (not only QUIET_S-fresh) so a slightly-stale-but-unprocessed ping still rides.
drain_scan() {
  local rf rv wc
  if [ -n "$UUID" ] && [ -s "$COORD/mailbox/$UUID.md" ]; then
    printf '── mailbox %s ──\n' "$UUID"; tail -40 "$COORD/mailbox/$UUID.md" 2>/dev/null
  fi
  if [ -d "$COORD/cc-roles" ]; then
    for rf in "$COORD"/cc-roles/*; do
      [ -f "$rf" ] || continue
      rv="$(cat "$rf" 2>/dev/null)"
      { [ "$rv" = "$SID" ] || { [ -n "$UUID" ] && [ "$rv" = "$UUID" ]; }; } || continue
      [ -s "$COORD/mailbox/$rv.md" ] && { printf '── mailbox role:%s → %s ──\n' "$(basename "$rf")" "$rv"; tail -40 "$COORD/mailbox/$rv.md" 2>/dev/null; }
    done
  fi
  if [ -d "$COORD/wait-contracts" ]; then
    for wc in "$COORD"/wait-contracts/*.json; do
      [ -f "$wc" ] || continue
      [ "$(jq -r '.status // empty' "$wc" 2>/dev/null)" = "OPEN" ] || continue
      ident_is_me "$(jq -r '.waitee // empty' "$wc" 2>/dev/null)" || continue
      printf '── inbound wait-contract %s ──\n' "$(basename "$wc")"; jq -rc '{waiter,expected_signal,deadline,heartbeat}' "$wc" 2>/dev/null
    done
  fi
}

# ── DECISION ROUTING (tiered context-refresh, 4ce6ffc0194f) ──────────────────────────────────────────
# The desk is TRIGGER-worthy (over eff_idle, or a floored rot tell). Route on desk STATE:
#   SAFE (idle)                     → fire_mode=idle → the shared fire machine (Stage 1/2/wedge), unchanged.
#   BUSY soft + HIGH ctx (≥ T_BUSY) → fire_mode=busy → the shared fire machine, DRAINING the ping queue.
#   BUSY hard + HIGH ctx            → busy-page (cannot safely force — surface, never bury).
#   BUSY + medium/low               → Tier-2: mark a refresh-queued intent + hold (the lowered idle
#                                     threshold fires it at the next idle gap).
mkdir -p "$STATE_DIR" 2>/dev/null || true
high_ctx=0; early_busy=0
{ [ "$fresh" = 1 ] && [ "$used" -ge "$T_BUSY" ]; } && high_ctx=1
# context-econ FORECAST-EARLY busy trigger (header §8): at high burn the 90% wall arrives before
# T_BUSY does — act while the advisory→grace→drain ladder still has LEAD_MIN of runway. Floor
# T_BUSY_MIN keeps mid-fill sessions from tripping on a burst; forecast -1 (unknown) never triggers.
if [ "$high_ctx" = 0 ] && [ "$fresh" = 1 ] && [ "$used" -ge "$T_BUSY_MIN" ] \
   && [ "$forecast_min" -ge 0 ] 2>/dev/null && [ "$forecast_min" -le "$LEAD_MIN" ]; then
  high_ctx=1; early_busy=1
fi
# SIZE AXIS ⇒ HIGH (header §9). An over-size session is dangerous regardless of fill, so it must not be
# parked in Tier-2 ("queue a refresh and hold") where the lowered idle bar would never fire it — the size
# axis is monotonic, so waiting cannot improve it. Marking it high routes it through the EXISTING tiers:
# BUSY soft ⇒ Tier-3 drain (shadow-composes + pages; exec still needs --live --busy-force), BUSY hard ⇒
# busy-page, SAFE ⇒ the idle Stage-1→2 ladder. That is where the "emergency page fallback" comes from.
size_busy=0
if [ "$high_ctx" = 0 ] && [ "$over_size" = 1 ]; then high_ctx=1; size_busy=1; fi
dod_carry="$("${DOD_PERSIST:-$(dirname "$0")/dod-persist.sh}" get 2>/dev/null || true)"
fire_mode=idle; drain_section=""

if [ "$SAFE" = 0 ]; then
  if [ "$high_ctx" = 1 ] && [ "$hold_class" = soft ]; then
    fire_mode=busy; drain_section="$(drain_scan)"             # Tier-3: force-recycle, carrying the pings
  elif [ "$high_ctx" = 1 ]; then
    # ── BUSY-PAGE — a HARD hold at high context. Forcing would lose state (sequencer/teammate) or bury a
    #    decision, so it will NOT recycle — page the operator OUT-OF-BAND (fleet-safe ⇒ ships LIVE),
    #    page-once per ESCALATE_DEDUP_S via escalated_for.
    if [ -f "$(escalated_for "$SID")" ]; then
      ep="$(cat "$(escalated_for "$SID")" 2>/dev/null || echo 0)"; case "$ep" in ''|*[!0-9]*) ep=0 ;; esac
      [ "$(( $(date +%s) - ep ))" -lt "$ESCALATE_DEDUP_S" ] && abstain "busy-page-paced:${hold_reason}"
    fi
    date +%s > "$(escalated_for "$SID")" 2>/dev/null || true
    log_idl escalated "busy-hard-hold:${hold_reason}" \
      "$(jq -cn --argjson used "$used" --arg hold "$hold_reason" --argjson busy 1 --argjson burn "$burn_x100" --argjson fc "$forecast_min" \
          '{used_pct:$used,hold:$hold,busy:($busy==1),forceable:false,burn_x100:$burn,forecast_min:$fc}')"
    # Axis-honest wording: on a SIZE fire the fill can be low, so the legacy "climbing toward the 90%
    # auto-compact wall" line would misdescribe the danger and invite the reader to dismiss it.
    if [ "$size_busy" = 1 ]; then
      pwhat="BUSY + OVERSIZE (transcript ${tx_mb}MB ≥ ${SIZE_MB}MB at only ${used}% context)"
      pwhy="Your transcript is past the size bar. Compaction does NOT shrink it — only a fresh session does, so this will not improve by waiting."
    else
      pwhat="BUSY + HIGH CONTEXT (${used}% ≥ ${T_BUSY}%)"
      pwhy="You are climbing toward the 90% auto-compact wall."
    fi
    wr_os_notify "Claude desk BUSY+HIGH" "desk ${UUID:-$SID} ${pwhat} mid-work (${hold_reason}) — can't safely auto-recycle"
    wr_push_page "BUSY+HIGH DESK (${DESK_ROLE}) ${used}% ctx / ${tx_mb}MB transcript, ${hold_reason} — resolve + /handoff; auto-recycle held (hard)"
    pmsg="⚠ ${pwhat} held by ${hold_reason} — a HARD hold: an auto-recycle would lose state or bury a decision, so it will NOT fire. ${pwhy} ACT NOW: resolve the ${hold_reason} (commit / finish the merge, answer the decision, or let the teammate finish), then run /handoff to recycle. Re-pages every ${ESCALATE_DEDUP_S}s. Kill-switch: \`waiting-recycle.sh clear\`."
    jq -nc --arg a "$pmsg" --arg s "$pmsg" \
      '{decision:"block",reason:$s,systemMessage:$s,hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$a}}'
    exit 0
  else
    # ── TIER 2 — BUSY at medium/low context. Don't interrupt the work; QUEUE a refresh (a soft hold marks
    #    intent; the lowered idle threshold fires it at the next idle gap) + hold with the specific reason.
    [ "$hold_class" = soft ] && { : > "$(queued_for "$SID")" 2>/dev/null || true; }
    # context-econ PAUSE-POINT NUDGE (header §8): from T_NUDGE up, a BUSY soft-held desk is no longer
    # held in SILENCE — tell the model (the only judge of a good boundary) to PLAN its pause-point
    # while the choice is cheap. Advisory-only: this branch can never fire a recycle; the idle path
    # and the busy ceiling keep that role. Own pacer, re-armed per +NUDGE_REARM pct fill (the
    # boundary-handoff B-2 shape — going silent while the fill climbs would be the bug). Soft-only:
    # a HARD hold (open decision / sequencer / teammate) must surface its own state, not a nudge.
    if [ "$fresh" = 1 ] && [ "$used" -ge "$T_NUDGE" ] && [ "$hold_class" = soft ]; then
      nf="$(nudged_for "$SID")"
      last_n="$(cat "$nf" 2>/dev/null || echo 0)"; case "$last_n" in ''|*[!0-9]*) last_n=0 ;; esac
      if [ "$last_n" = 0 ] || [ $(( used - last_n )) -ge "$NUDGE_REARM" ]; then
        printf '%s' "$used" > "$nf" 2>/dev/null || true
        log_idl fired "busy-nudge:${hold_reason}" \
          "$(jq -cn --argjson used "$used" --arg hold "$hold_reason" --argjson burn "$burn_x100" --argjson fc "$forecast_min" \
              '{used_pct:$used,hold:$hold,burn_x100:$burn,forecast_min:$fc}')"
        # M-3: the DURABLE, self-describing outcome record. `nudged` — an advisory, NOT a recycle.
        # Two of the three `fired` records in the entire live IDL were this branch; the enum makes
        # that impossible to miscount ever again.
        command -v ce_record_recycle >/dev/null 2>&1 && \
          ce_record_recycle "$tel" nudged "$used" "busy-nudge" "${fire_mode:-busy}" || true
        if [ "$hold_reason" = "operator-conversing-hold" ]; then
          nmsg="⟳ CONTEXT PAUSE-POINT PLANNING — a live exchange is in flight and context is ${used}% (≥ ${T_NUDGE}%). Do NOT cut the exchange; DO plan its landing: at the natural end of this exchange, persist the decisions it produced (dod-persist / plan / memory), commit any in-hand work, then run /handoff to recycle into a fresh successor. The forced drain engages at ${T_BUSY}% (or sooner at high burn). (paced: re-advises per +${NUDGE_REARM}% fill)"
        else
          nmsg="⟳ CONTEXT PAUSE-POINT PLANNING — you are mid-work (${hold_reason}) at ${used}% (≥ ${T_NUDGE}%). Plan your own pause-point NOW while the choice is cheap: finish the in-hand step, commit, persist open decisions, then run /handoff at that natural boundary to recycle. If you ride on, the forced drain engages at ${T_BUSY}% (or sooner at high burn). (paced: re-advises per +${NUDGE_REARM}% fill)"
        fi
        jq -nc --arg a "$nmsg" --arg s "$nmsg" \
          '{decision:"block",reason:$s,systemMessage:$s,hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$a}}'
        exit 0
      fi
    fi
    log_idl abstained "$hold_reason" \
      "$(jq -cn --argjson used "$used" --arg cls "$hold_class" --argjson burn "$burn_x100" --argjson fc "$forecast_min" \
          '{used_pct:$used,hold_class:$cls,refresh_queued:($cls=="soft"),burn_x100:$burn,forecast_min:$fc}')"
    exit 0
  fi
fi
# Reaching here: fire_mode=idle (SAFE) OR fire_mode=busy (BUSY soft + high ctx). The SHARED fire machine.

# trig label — honest to the actual gate (eff_idle for idle; T_BUSY / the burn forecast / the SIZE axis for
# busy). The size branches come FIRST where they are the reason: a size fire that narrated itself as
# "context N% ≥ T_BUSY%" would be a lie about which axis fired — and the whole point of K02 is that the two
# axes disagree. Wrong narration here is how the next reader concludes the size trigger never fires.
if   [ "$fire_mode" = busy ] && [ "$size_busy" = 1 ];        then trig="transcript ${tx_mb}MB ≥ ${SIZE_MB}MB (context only ${used}% — SIZE, not fill) while BUSY (${hold_reason})"
elif [ "$fire_mode" = busy ] && [ "$early_busy" = 1 ];       then trig="context ${used}% burning ~$(( burn_x100 / 100 )).$(( burn_x100 % 100 / 10 ))%/min — forecast ≤${forecast_min}min to the ${CC_CE_WALL:-88}% wall while BUSY (${hold_reason})"
elif [ "$fire_mode" = busy ];                                then trig="context ${used}% ≥ ${T_BUSY}% while BUSY (${hold_reason})"
elif [ "$over_size" = 1 ] && [ "$over_threshold" = 1 ];     then trig="transcript ${tx_mb}MB ≥ ${SIZE_MB}MB AND context ${used}% ≥ ${eff_idle}%"
elif [ "$over_size" = 1 ];                                  then trig="transcript ${tx_mb}MB ≥ ${SIZE_MB}MB (context only ${used}% — the SIZE axis, which compaction does not reset)"
elif [ "$over_threshold" = 1 ] && [ "$rot_valid" = 1 ];     then trig="context ${used}% ≥ ${eff_idle}% AND a state-rot tell"
elif [ "$over_threshold" = 1 ];                             then trig="context ${used}% ≥ ${eff_idle}%"
else                                                             trig="a floored state-rot tell (re-deriving known state, ${used}% ≥ ${ROT_FLOOR}% floor)"
fi

# Already fired for THIS SID? one-fire-per-SID latch. A LIVE fire recycles to a fresh SID, so this only
# re-hits in SHADOW. If the desk is WEDGED (still fire-worthy) it routes to the escalate branch below
# (T-P1-8) instead of a silent already-fired; otherwise (cooled/paced — already handled in the fast-path
# above) stay quiet. Placed before Stage 2 so a re-poll never double-fires.
{ [ "$stage2_pending" = 0 ] && [ -f "$firedf" ] && [ "$wedged" = 0 ]; } && abstain "already-fired"

# ════ STAGE 2 — deterministic FIRE (cooldown+cap EXEMPT; bound = one-fire-per-SID latch) ════
if [ "$stage2_pending" = 1 ]; then
  # ── RECENT-CONVERSATION GRACE (context-econ, header §8) ──────────────────────────────────────────
  # S6 HOLDS a fresh interactive turn (conv_age < CONV_HOLD_S). Just ABOVE that window a real 2-way
  # exchange has only just quieted — discarding it on the standard GRACE_S=180 is too eager. When an
  # interactive turn exists in [CONV_HOLD_S, CONV_RECENT_S), the IDLE Stage-2 fire waits the longer
  # RECENT_GRACE_S from the first advisory before it may fire (or shadow-fire). Idle-only: a BUSY+high
  # desk is genuinely context-starved and must not linger. conv_age unknown/"" ⇒ legacy grace (no hold).
  extended_grace=0
  if [ "$fire_mode" = idle ] && [ -n "$conv_age" ] \
     && [ "$conv_age" -ge "$CONV_HOLD_S" ] && [ "$conv_age" -lt "$CONV_RECENT_S" ]; then
    extended_grace=1
    est_rg="$(cat "$escf" 2>/dev/null)"; case "$est_rg" in ''|*[!0-9]*) est_rg=0 ;; esac
    if [ "$est_rg" -gt 0 ] && [ "$(( $(date +%s) - est_rg ))" -lt "$RECENT_GRACE_S" ]; then
      log_idl abstained "recent-conversation-grace" \
        "$(jq -cn --argjson used "$used" --arg conv "$conv_age" --argjson grace "$RECENT_GRACE_S" \
            '{used_pct:$used,conv_age_s:$conv,extended_grace_s:$grace,mode:"idle"}')"
      exit 0
    fi
  fi
  : > "$firedf" 2>/dev/null                                   # latch FIRST — at-most-once per SID even on re-entry
  # Compose the successor brief ATOMICALLY (tmp+mv). NEVER empty/partial → no task-less successor (FM-D):
  #   standing --brief template (if armed) + frozen DoD + (busy) the drained ping queue + a re-derive directive.
  FIRE_DIR="${CC_WR_FIRE_DIR:-/tmp}"; pf="$FIRE_DIR/wr-fire-${SID}.txt"; tmpf="$pf.$$"
  _szmw=""; [ "$fire_mode" = busy ] && _szmw=", and it was FORCED mid-work rather than at a clean boundary"
  {
    if [ -s "$(brief_for "$CWD")" ]; then cat "$(brief_for "$CWD")"
    elif [ "$over_size" = 1 ]; then printf '%s\n' "You are the monitoring DESK, resumed by a deterministic self-recycle triggered by SIZE, not context fill: the predecessor's transcript had reached ${tx_mb}MB (≥ ${SIZE_MB}MB) at only ${used}% context${_szmw}. A transcript is never reset by compaction — only a fresh session resets it — which is why this fired while every context-fill trigger read the desk as healthy."
    elif [ "$fire_mode" = busy ] && [ "$early_busy" = 1 ]; then printf '%s\n' "You are the monitoring DESK, resumed by a deterministic self-recycle FORCED mid-work (predecessor context was ${used}% full and BURNING toward the auto-compact wall — forecast ≤${forecast_min}min at the observed rate — so it was discarded before rot/exhaustion)."
    elif [ "$fire_mode" = busy ]; then printf '%s\n' "You are the monitoring DESK, resumed by a deterministic self-recycle FORCED mid-work (predecessor context was ${used}% full — over the ${T_BUSY}% busy ceiling — and has been discarded to stop context rot)."
    else printf '%s\n' "You are the monitoring DESK, resumed by a deterministic self-recycle (predecessor context was ${used}% full and has been discarded to stop context rot)."; fi
    [ -n "$dod_carry" ] && printf '\nScope (frozen): %s\n' "$dod_carry"
    if [ "$fire_mode" = busy ]; then
      printf '\nNOTE — this recycle was FORCED while the desk was mid-work (%s). The working tree and any coordination state are on DISK; inspect git status / git diff and act on the drained pings below before assuming a clean slate.\n' "$hold_reason"
      [ -n "$drain_section" ] && printf '\nPENDING PINGS/REQUESTS TO CARRY (drained at recycle — do NOT drop; act on these after re-deriving state):\n%s\n' "$drain_section"
    fi
    printf '\nFIRST ACTION — re-derive live watch state from DISK (the predecessor context is GONE; do not assume): run cc-board for the fleet roster; read the live-session registry, ~/.claude/wait-contracts (owned waits), and your role mailbox; scan worktrees + git for wave/merge state. Then resume monitoring. Do NOT re-arm waiting-recycle (the arm survives the recycle; re-arming clears the loop-breaker).\n'
  } > "$tmpf" 2>/dev/null
  if [ -s "$tmpf" ]; then mv -f "$tmpf" "$pf" 2>/dev/null; else rm -f "$tmpf" 2>/dev/null; fi
  if [ ! -s "$pf" ]; then log_idl abstained "fire-compose-empty" "$(jq -cn --argjson used "$used" '{used_pct:$used}')"; exit 0; fi
  # 3-way, not 2-way: with the size axis a boolean threshold/behavioral label would file every size fire
  # under "behavioral", making the new axis invisible in exactly the ledger built to prove it fires.
  if   [ "$over_size" = 1 ];       then tk=size
  elif [ "$over_threshold" = 1 ];  then tk=threshold
  else                                  tk=behavioral
  fi
  # EXEC gate: idle ⇒ armed --live. busy ⇒ armed --live AND the extra busy-force opt-in (a mid-work recycle
  # is qualitatively riskier than an idle one — it needs its own arm beyond --live). Else SHADOW.
  exec_ok=0
  if [ -f "$(live_for "$CWD")" ]; then
    if [ "$fire_mode" = idle ]; then exec_ok=1
    elif [ -f "$(busyforce_for "$CWD")" ] || [ "${CC_WR_BUSY_FORCE:-}" = on ]; then exec_ok=1; fi
  fi
  if [ "$exec_ok" = 1 ]; then
    date +%s > "$cf" 2>/dev/null || true                      # anchor the cross-generation loop-breaker on the FIRE
    # M-3: `executed` — the ONLY verdict that means a context was actually replaced. Measured across
    # the whole live IDL before this landed: ZERO stage2-live records in 32,075 evaluations. This
    # record is what makes that number readable instead of inferred from an overloaded token.
    command -v ce_record_recycle >/dev/null 2>&1 && \
      ce_record_recycle "$tel" executed "$used" "$tk" "$fire_mode" || true
    log_idl fired "stage2-live" \
      "$(jq -cn --argjson used "$used" --arg trigger "$tk" --arg mode "$fire_mode" --arg prompt_file "$pf" --argjson grace_s "$GRACE_S" \
          --argjson burn "$burn_x100" --argjson fc "$forecast_min" --argjson early "$early_busy" --argjson eg "$extended_grace" \
          '{used_pct:$used,trigger:$trigger,mode:$mode,prompt_file:$prompt_file,grace_s:$grace_s,burn_x100:$burn,forecast_min:$fc,early_busy:($early==1),extended_grace:($eg==1)}')"
    # Sanctioned actuator: it arms a DETACHED watcher BEFORE typing /exit (order load-bearing), so the
    # recycle completes even when the /exit interrupt SIGKILLs this hook's process group.
    "$HANDOFF_FIRE" --recycle --prompt-file "$pf" ${UUID:+--session-id "$UUID"} </dev/null >/dev/null 2>&1 || true
    fmsg="⟳ DETERMINISTIC RECYCLE FIRED (${trig}) — the desk did not self-recycle within the ${GRACE_S}s grace, so waiting-recycle fired handoff-fire.sh --recycle. The successor is launching in this pane with the frozen DoD + a re-derive-from-disk brief. Do NOT run handoff-fire yourself."
    jq -nc --arg r "$fmsg" '{decision:"block",reason:$r,systemMessage:$r,hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$r}}'
    exit 0
  fi
  # SHADOW (default): everything a live fire does EXCEPT the exec — ships the mechanism DAMPED so a gate
  # bug cannot strand the fleet before the operator reviews the shadow log and arms live (damp-first). A
  # BUSY shadow is more urgent than idle (mid-work AND high), so it ALSO pages out-of-band.
  # M-3: `shadow-would-fire` — everything a live fire does EXCEPT the exec. Distinguishing this from
  # `executed` is the whole point of the enum: they were the same token, so the shadow soak was
  # indistinguishable from a working recycle in every downstream count.
  command -v ce_record_recycle >/dev/null 2>&1 && \
    ce_record_recycle "$tel" shadow-would-fire "$used" "$tk" "$fire_mode" || true
  log_idl fired "stage2-shadow" \
    "$(jq -cn --argjson used "$used" --arg trigger "$tk" --arg mode "$fire_mode" --arg prompt_file "$pf" --argjson grace_s "$GRACE_S" \
        --argjson burn "$burn_x100" --argjson fc "$forecast_min" --argjson early "$early_busy" --argjson eg "$extended_grace" \
        '{used_pct:$used,would_fire:true,trigger:$trigger,mode:$mode,prompt_file:$prompt_file,grace_s:$grace_s,burn_x100:$burn,forecast_min:$fc,early_busy:($early==1),extended_grace:($eg==1)}')"
  if [ "$fire_mode" = busy ]; then
    wr_os_notify "Claude desk BUSY+HIGH would-recycle" "desk ${UUID:-$SID} at ${used}% mid-work (${hold_reason}); drained brief at ${pf}"
    wr_push_page "BUSY+HIGH would-recycle (${DESK_ROLE}) ${used}%: drained brief at ${pf} — /handoff now or arm --busy-force"
    smsg="⟳ BUSY+HIGH RECYCLE WOULD FIRE — SHADOW (${trig}). The desk is mid-work (${hold_reason}) and did not self-recycle within ${GRACE_S}s. waiting-recycle composed a successor brief WITH the drained ping queue at ${pf} and logged a would-fire, but did NOT exec (a mid-work auto-recycle is opt-in beyond --live). Self-recycle now: run /handoff (it captures the same pings). To enable the exec: waiting-recycle.sh arm --brief <file> --live --busy-force. Kill-switch: waiting-recycle.sh clear."
  else
    smsg="⟳ RECYCLE WOULD FIRE — SHADOW (${trig}). The desk did not self-recycle within ${GRACE_S}s. waiting-recycle is armed SHADOW: it composed the successor brief at ${pf} and logged a would-fire, but did NOT exec (no fleet-stranding risk while soaking). You SHOULD still self-recycle now: run /handoff. To enable the exec after review: waiting-recycle.sh arm --brief <file> --live. Kill-switch: waiting-recycle.sh clear."
  fi
  jq -nc --arg a "$smsg" --arg s "$smsg" '{decision:"block",reason:$s,systemMessage:$s,hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$a}}'
  exit 0
fi

# ════ T-P1-8 ESCALATE — a WEDGED desk (advisory CAP reached / SHADOW would-fire latched) that is STILL
#     fire-worthy pages the operator OUT-OF-BAND rather than silently riding to the 90% auto-compact wall.
#     Paging is fleet-SAFE, so this ships LIVE. Page-once per ESCALATE_DEDUP_S via the escalated_for pacer. ═
if [ "$wedged" = 1 ]; then
  date +%s > "$(escalated_for "$SID")" 2>/dev/null || true   # stamp the page-once pacer FIRST (at-most-once/window)
  livearm="--live"; [ "$fire_mode" = busy ] && livearm="--live --busy-force"
  if [ "$capped" = 1 ]; then why="advisory budget exhausted (${N}/${MAX}), no recycle"
  else                        why="a SHADOW would-fire is latched but the exec is not armed ${livearm}"; fi
  state_phrase="clean tree + no open decision"; [ "$fire_mode" = busy ] && state_phrase="mid-work (${hold_reason})"
  log_idl escalated "wedge:${why}" \
    "$(jq -cn --argjson used "$used" --arg why "$why" --arg mode "$fire_mode" --argjson capped "$capped" --argjson shadow "$shadow_fired" \
        '{used_pct:$used,why:$why,mode:$mode,capped:($capped==1),shadow_fired:($shadow==1)}')"
  wr_os_notify "Claude desk WEDGED" "desk ${UUID:-$SID} at ${used}% can't self-recycle — ${why}"
  wr_push_page "WEDGED DESK (${DESK_ROLE}) ${used}% ctx: ${why} — /handoff now or arm ${livearm}"
  emsg="⚠ WEDGED — quiet monitoring boundary (${trig}), ${state_phrase}, but ${why}: you are RIDING toward the 90% auto-compact wall with NO recycle. ACT NOW: run /handoff to self-recycle, or (operator) arm the deterministic exec — desk-arm-live.sh (or waiting-recycle.sh arm --brief <file> ${livearm}). Re-pages every ${ESCALATE_DEDUP_S}s until resolved. Kill-switch: waiting-recycle.sh clear (this desk) / kill (global)."
  jq -nc --arg a "$emsg" --arg s "$emsg" \
    '{decision:"block",reason:$s,systemMessage:$s,hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$a}}'
  exit 0
fi

# ════ STAGE 1 — advisory (cooldown + cap already cleared above for this branch) ════
date +%s > "$cf" 2>/dev/null || true                         # stamp cooldown (anti-thrash + loop-breaker)
printf '%s' "$((N + 1))" > "$capf" 2>/dev/null || true       # bump advisory cap
[ -f "$escf" ] || date +%s > "$escf" 2>/dev/null || true     # set the Stage-2 grace clock on the FIRST advisory
if   [ "$over_size" = 1 ];      then tk1=size
elif [ "$over_threshold" = 1 ]; then tk1=threshold
else                                 tk1=behavioral
fi
# M-3: `advised` — Stage-1 told the model to recycle; nothing executed. This branch logged the
# reason string "waiting-recycle", which reads like the mechanism firing rather than an advisory.
command -v ce_record_recycle >/dev/null 2>&1 && \
  ce_record_recycle "$tel" advised "$used" "$tk1" "$fire_mode" || true
log_idl fired "waiting-recycle" \
  "$(jq -cn --arg trigger "$tk1" --arg mode "$fire_mode" \
      --argjson used "$used" --argjson rot "$rot_valid" --argjson count "$((N+1))" --argjson max "$MAX" \
      --argjson burn "$burn_x100" --argjson fc "$forecast_min" --arg conv "${conv_age:-}" \
      '{trigger:$trigger,mode:$mode,used_pct:$used,rot:$rot,count:$count,max:$max,burn_x100:$burn,forecast_min:$fc,conv_age_s:$conv}')"

if [ "$fire_mode" = busy ]; then
  # BUSY advisory — mid-work at high context. Urge a self-/handoff NOW (it captures the same pings); if
  # ignored, the shadow would-force (or, opted-in, the exec) escalates after grace.
  # "climbing toward the wall" is only true on the FILL axis; a size fire can sit at low fill (K02), and a
  # misdescribed danger is one the reader dismisses. ${trig} already names the real axis.
  if [ "$size_busy" = 1 ]; then advwhy="your transcript is past the size bar and compaction will not shrink it — only a fresh session will"
  else                          advwhy="you are climbing toward the 90% auto-compact wall"; fi
  adv="⟳ BUSY + HIGH-CONTEXT AUTO-RECYCLE — ${trig}: ${advwhy}. RECYCLE NOW while you still can cleanly: run /handoff — it captures the live state INCLUDING the pending pings/requests (mailbox + inbound wait-contracts) into the payload and fires handoff-fire.sh --recycle so the SUCCESSOR PANE IS THE CONTINUATION with nothing dropped. Commit any in-hand edit first (the working tree survives the recycle, but a fresh desk shouldn't inherit an unexplained diff). If you ignore this, the deterministic drain-and-recycle escalates in ${GRACE_S}s. Kill-switch: \`waiting-recycle.sh clear\` (this desk) / \`waiting-recycle.sh kill\` (global). (busy auto-recycle advisory $((N+1))/${MAX})"
else
  adv="⟳ MONITORING AUTO-RECYCLE — you are at a quiet monitoring boundary (${trig}). A watching desk accrues low-value context that rots your recall of the load-bearing orchestration state. RECYCLE NOW via your existing self-recycle path: run /handoff — it captures the live state (fired sessions, pending pings, wave/merge state, decisions) into the payload and fires handoff-fire.sh --recycle so the SUCCESSOR PANE IS THE CONTINUATION and this bloated context is discarded. Do it as this turn's next action. IF instead you actually hold in-hand write-work or a genuine open decision (you should not — the tree is clean and no blocker was detected), do NOT recycle: surface it. If you ignore this, the deterministic fire escalates in ${GRACE_S}s. Kill-switch: \`waiting-recycle.sh clear\` (this desk) / \`waiting-recycle.sh kill\` (global). (auto-recycle advisory $((N+1))/${MAX})"
fi
# ── carry the mission/DoD line so a recycle never loses purpose (T-P4-4; empty = none recorded) ──
[ -n "$dod_carry" ] && adv="${adv}

⟳ MISSION TO CARRY: ${dod_carry} — restate this verbatim as the successor's \`Scope (frozen):\` line in your /handoff payload so the recycle keeps its purpose (never drop or narrow it)."
sysmsg="⟳ waiting-recycle: desk at a quiet boundary (${trig}) — advising /handoff self-recycle ($((N+1))/${MAX}); deterministic fire in ${GRACE_S}s if ignored."

jq -nc --arg a "$adv" --arg s "$sysmsg" \
  '{decision:"block", reason:$s, systemMessage:$s, hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$a}}'
exit 0
