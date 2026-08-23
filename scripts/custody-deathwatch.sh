#!/usr/bin/env bash
# custody-deathwatch.sh — the out-of-process arm of the custody invariant:
#   A FINISHED — OR DYING — PEER SESSION CAN NEVER VANISH WITHOUT ITS ORIGINATOR LEARNING OF IT.
#
# ── THE GAP THIS CLOSES (measured 2026-08-23) ────────────────────────────────────────────────────
# bin/cc-custody records a debt at every dispatched fire and every consumer of that debt is a
# TURN-BOUNDARY HOOK scoped to the originator's own cwd (wrap-ledger CUSTODY_OPEN, completion-assert,
# session-continue's wake floor, operator-readout). That design has exactly two blind spots, and both
# were measured, not theorised:
#
#   1. NOBODY IS HOME. `cc-offload` opens with `--cwd "$PWD"` and
#      `${ITERM_SESSION_ID:+--originator-pane …}`. Cloud fires come from the launchd dispatcher, whose
#      cwd is `/` and which has no ITERM_SESSION_ID — so all 175 open cloud rows carry cwd `/`, NO
#      originatorPane and NO notifyBack. `scripts/cloud-return.sh` faithfully detects the outcome and
#      then has no address to send it to: **1055 of its 1116 wake attempts recorded "the declaration
#      names no notify-back target — nothing to wake"** (61 real wakes, 94.5% discarded). The news is
#      produced and thrown away. And because no interactive session's cwd is ever `/`, no `--cwd .`
#      consumer has ever rendered those rows either.
#
#   2. THE PEER CANNOT REPORT ITS OWN SIGKILL. The local lane discharges from
#      `handoff-fire.sh sc_announce_before_retire` (an in-process step) or from a HANDOFF-PING the
#      peer sends. A `kill -9` / `timeout -k` runs neither. Panes 377 (`fire-d56a874d9441`) and 552
#      (`fire-undo-build`) are the surviving proof: dead, custody open, nothing ever told anyone.
#
# The common shape: **every existing sensor asks the peer, or asks the originator's own turn.** When
# the peer is killed and the originator is a cron job, there is no one left to ask. Twenty
# reap/orphan/alarm scripts ship in this repo and **not one of them mentions custody** (grep, 2026-08-23).
#
# ── WHAT THIS DOES ───────────────────────────────────────────────────────────────────────────────
# One periodic pass, out of process, driven from autonomy-sweep (already launchd-resident):
#   1. Read the open set STORE-WIDE — `cc-custody list --open --json` with NO `--cwd`. This is the
#      only consumer that deliberately drops the cwd scope, which is precisely how it sees the `/`
#      shard that every other consumer is blind to by construction.
#   2. Ask an oracle that does NOT depend on the peer's cooperation whether that peer still lives.
#   3. Report the ones that are gone — ONCE each, ever — to an address that exists by construction.
# It NEVER discharges a debt, never closes a row, never kills a process. Detection is not disposition.
#
# ── THE THREE-VALUED ORACLE, AND WHY THE FLOOR IS ORACLE-INDEPENDENT ─────────────────────────────
#   GONE    — the oracle RAN and the peer is not among the living ⇒ report NOW, at any age. This is
#             the abnormal-death fast path: a SIGKILLed pane is exactly what an external oracle sees.
#   ALIVE   — the oracle RAN and found it ⇒ report NEVER. Nagging over live work is the opposite
#             failure and the brief names it as the worse one.
#   UNKNOWN — the oracle could not run (cc-cloud 401s, cc-pane absent, id pruned). A lookup MISS is
#             not absence (memory: lookup-miss-is-not-absence), so this may never mint a GONE.
#
# UNKNOWN is where the previous design died, so it gets its own rule. `cloud-return.sh` already
# abstains correctly on an unreadable control plane — and **six days of correct abstention produced
# zero signal to any human**, which is the same silence with better manners. So the report condition
# is a DISJUNCTION, and its second arm needs no oracle at all:
#
#       REPORT  ⇔  ( oracle says GONE )  OR  ( row is STALE, i.e. age ≥ CC_CUSTODY_TTL_HOURS )
#
# The staleness arm reads only the row's own `ts`, which is always present and always readable.
# **An oracle outage therefore degrades the WORDS of the report, never its EXISTENCE.** That is the
# single most important property in this file: the alarm keys on the store, not on the sensor.
#
# ── FAILURE DIRECTION (stated, per the DoD) ──────────────────────────────────────────────────────
# This script can only ever ADD a notification. It cannot discharge custody, cannot close a backlog
# row, cannot signal a process, cannot touch a branch or a worktree. Its worst failure is therefore
# OPERATOR NOISE — telling someone about a peer that was actually fine. Its counterfactual is the
# defect it exists to end: SILENCE over lost work. Noise is recoverable in one read; silence has
# already cost 62 content-stranded commits across 21 branches. So the bias is deliberate:
#   · uncertain about liveness  → still report (via the stale floor), never stay quiet
#   · uncertain about the peer  → NEVER mint GONE from a failed oracle (that would be a false death)
#   · uncertain about anything  → NEVER discharge (only a human/agent verdict discharges)
# The noise is bounded by a per-marker latch (once ever) and by aggregation (one operator row per
# pass, not one per peer) — so the alarm cannot become the always-firing kind that carries no bits
# (memory: alarm-polarity-and-attention-budget).
#
# ── ADDRESSING ───────────────────────────────────────────────────────────────────────────────────
#   1. `originatorPane` present AND that pane is alive ⇒ `cc-notify <pane>` — the originator LEARNS
#      through the channel it already reads. This is the local lane's fix.
#   2. otherwise ⇒ ONE aggregated `cc-backlog needs` row, which `operator-readout.sh` renders into
#      the counted OPERATOR ▸ block at every close. This is the cloud lane's fix: it replaces an
#      address that does not exist with a store that is read by construction.
# A peer whose originator is gone is the common case, not the exotic one — 175 of 179 open rows have
# no originator at all — so path 2 is the load-bearing one.
#
# Env seams (tests): CC_CUSTODY_DIR · CC_CUSTODY_TTL_HOURS · CC_DEATHWATCH_STATE ·
#   CC_DEATHWATCH_CUSTODY_BIN · CC_DEATHWATCH_NOTIFY_BIN · CC_DEATHWATCH_BACKLOG_BIN ·
#   CC_DEATHWATCH_PANE_BIN · CC_DEATHWATCH_CLOUD_BIN · CC_DEATHWATCH_DEPLOYED (guard override)
set -uo pipefail

STATE="${CC_DEATHWATCH_STATE:-$HOME/.claude/autonomy/custody-deathwatch}"
LEDGER="$STATE/deathwatch.jsonl"
TTL_HOURS="${CC_CUSTODY_TTL_HOURS:-24}"
case "$TTL_HOURS" in ''|*[!0-9]*) TTL_HOURS=24 ;; esac

DRY=0; SELFTEST=0
for a in "$@"; do
  case "$a" in
    --dry-run)  DRY=1 ;;
    --selftest) SELFTEST=1 ;;
    --sweep)    : ;;
    *) printf 'custody-deathwatch: unknown arg: %s\n' "$a" >&2; exit 2 ;;
  esac
done

say() { printf '%s\n' "$*"; }
now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# resolve <override> <name> <fallback…> — the same shape cloud-return.sh uses, so a test can swap
# any dependency out without this file knowing it is under test.
resolve() {
  local override="$1"; shift
  if [ -n "$override" ]; then [ -x "$override" ] && { printf '%s' "$override"; return 0; }; return 1; fi
  local n="$1"; shift
  local p; p="$(command -v "$n" 2>/dev/null)"; [ -n "$p" ] && { printf '%s' "$p"; return 0; }
  for c in "$@"; do [ -x "$c" ] && { printf '%s' "$c"; return 0; }; done
  return 1
}

# RESOLVED before the '..' traversal, and the two uses of this file's own path are deliberately
# DIFFERENT (self-path-lint would flag the unresolved form here, correctly):
#   · ROOT — a sibling-binary FALLBACK. ~/.claude/{scripts,hooks,bin}/ are per-file symlinks into
#     the checkout, so an unresolved `$0/..` from the deployed copy lands in ~/.claude and misses
#     ../bin entirely. It must resolve.
#   · the DEPLOYED guard below — reads `$0` UNRESOLVED on purpose, because resolving it follows the
#     deployed symlink back into the checkout and erases the only difference there is
#     (autonomy-sweep.sh records the incident that bought that rule).
# Same file, opposite requirements: one asks "where do my siblings live", the other asks "which copy
# of me is running".
_self="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
ROOT="$(cd "$(dirname "$_self")/.." 2>/dev/null && pwd)" || ROOT=""
CUSTODY_BIN="$(resolve "${CC_DEATHWATCH_CUSTODY_BIN:-}" cc-custody "$ROOT/bin/cc-custody" "$HOME/.claude/bin/cc-custody")" || CUSTODY_BIN=""
NOTIFY_BIN="$(resolve  "${CC_DEATHWATCH_NOTIFY_BIN:-}"  cc-notify  "$ROOT/bin/cc-notify"  "$HOME/.claude/bin/cc-notify")"   || NOTIFY_BIN=""
BACKLOG_BIN="$(resolve "${CC_DEATHWATCH_BACKLOG_BIN:-}" cc-backlog "$ROOT/bin/cc-backlog" "$HOME/.claude/bin/cc-backlog")" || BACKLOG_BIN=""
PANE_BIN="$(resolve    "${CC_DEATHWATCH_PANE_BIN:-}"    cc-pane    "$ROOT/bin/cc-pane"    "$HOME/.claude/bin/cc-pane")"     || PANE_BIN=""
CLOUD_BIN="$(resolve   "${CC_DEATHWATCH_CLOUD_BIN:-}"   cc-cloud   "$ROOT/bin/cc-cloud"   "$HOME/.claude/bin/cc-cloud")"    || CLOUD_BIN=""

command -v jq >/dev/null 2>&1 || { printf 'custody-deathwatch: jq not found\n' >&2; exit 3; }

# ── the oracles ──────────────────────────────────────────────────────────────────────────────────
# Each caches ONE reading per pass and records whether it could run at all. The distinction between
# "the oracle ran and the id is absent" and "the oracle could not run" is the whole three-valued
# design; collapsing them is how a blind sensor mints false deaths.
PANE_LIST=""; PANE_OK=0
load_pane_oracle() {
  [ -n "$PANE_BIN" ] || { PANE_OK=0; return 0; }
  local out rc
  out="$("$PANE_BIN" list 2>/dev/null)"; rc=$?
  # rc is READ, never discarded: an empty list from a working oracle means "no panes", while an
  # empty list from a broken one means "I could not look", and those must not be the same answer.
  if [ "$rc" -eq 0 ]; then PANE_LIST="$out"; PANE_OK=1; else PANE_OK=0; fi
}

CLOUD_STATES=""; CLOUD_OK=0
CLOUD_TIMEOUT_S="${CC_DEATHWATCH_CLOUD_TIMEOUT_S:-60}"
load_cloud_oracle() {
  [ -n "$CLOUD_BIN" ] || { CLOUD_OK=0; return 0; }
  local out rc tmo
  # 🚨 `--state` IS LOAD-BEARING, and omitting it produced a VACUOUS ORACLE that reported success.
  # Measured 2026-08-23: `cc-cloud list --json` exits 0 with 149 KB of rows carrying
  # id/branch/account/age_s and NO `state` key at all. The first version of this function read that,
  # mapped every row through `.state // "UNKNOWN"`, and set CLOUD_OK=1 — so the pass logged
  # `cloud_oracle_ok:true` while knowing nothing about any peer, which is a false green on the very
  # instrument this file uses to avoid false greens. Only `--state` asks the control plane.
  #
  # BOUNDED, because `--state` is a per-session control-plane round trip: the same call took rc 124
  # at 90 s on the live 260-declaration store. A cut oracle is a NON-VERDICT (rc must be 0), never a
  # partial reading — adopting half a census would let an unqueried peer read as absent.
  tmo="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || true)"
  if [ -n "$tmo" ]; then out="$("$tmo" "$CLOUD_TIMEOUT_S" "$CLOUD_BIN" list --state --json 2>/dev/null)"; rc=$?
  else out="$("$CLOUD_BIN" list --state --json 2>/dev/null)"; rc=$?; fi
  [ "$rc" -eq 0 ] && [ -n "$out" ] || { CLOUD_OK=0; return 0; }

  CLOUD_STATES="$(printf '%s' "$out" | jq -r '(if type=="array" then . else (.sessions // .rows // []) end)[]
                      | [(.id // .session_id // ""), (.state // "")] | @tsv' 2>/dev/null)" || { CLOUD_OK=0; return 0; }

  # THE SAMPLE MUST CARRY THE FIELD THE VERDICT NEEDS (memory: guard-sample-fields-bound-its-blind-spot).
  # A response that parsed but carries no state on ANY row has not answered the question, so it is
  # blindness — not a store full of row-level UNKNOWNs. The distinction decides whether the ledger
  # records `cloud_oracle_ok:false` (visible, actionable) or lies. Note the discrimination is
  # "no row has ANY state", not "some row says UNKNOWN": cc-cloud's own UNKNOWN is a real verdict
  # meaning it could not measure THAT session, and must stay a row-level answer.
  local with_state
  with_state="$(printf '%s\n' "$CLOUD_STATES" | awk -F'\t' '$2 != "" {n++} END{print n+0}')"
  [ "$with_state" -gt 0 ] && CLOUD_OK=1 || CLOUD_OK=0
}

# peer_disposition <targetPane> → prints ALIVE | GONE | UNKNOWN
peer_disposition() {
  local tp="$1"
  case "$tp" in
    cloud:*)
      [ "$CLOUD_OK" -eq 1 ] || { printf 'UNKNOWN'; return 0; }
      local sid="${tp#cloud:}" st
      st="$(printf '%s\n' "$CLOUD_STATES" | awk -F'\t' -v id="$sid" '$1==id {print $2; exit}')"
      case "$st" in
        ALIVE|BOOTING|RUNNING)                 printf 'ALIVE' ;;
        LANDED|ABANDONED|STALLED|NOT-STARTED)  printf 'GONE'  ;;
        # An id the arbiter does not carry is a MISS, and a miss is not absence. It may have been
        # pruned from the declaration store while the session itself is untouched.
        *)                                     printf 'UNKNOWN' ;;
      esac ;;
    ''|-)
      printf 'UNKNOWN' ;;
    *)
      # A local pane id. `cc-pane list` enumerates the living; absence from a list the oracle
      # successfully produced is the only evidence of death this box can offer.
      [ "$PANE_OK" -eq 1 ] || { printf 'UNKNOWN'; return 0; }
      local hit
      # EXACT equality, never a substring: `index($0,"60")` matches 602, 600 AND 605, so a substring
      # oracle would report a dead pane 60 as alive off any of its neighbours — and, worse, would
      # answer ALIVE for a pane that never existed. Trim first: the enumerator's rows may carry
      # surrounding whitespace, and `$1` alone would drop a multi-field row's identity.
      hit="$(printf '%s\n' "$PANE_LIST" | awk -v want="$tp" '{gsub(/^[ \t]+|[ \t]+$/,"")} $0==want {n++} END{print n+0}')"
      [ "$hit" -gt 0 ] && printf 'ALIVE' || printf 'GONE' ;;
  esac
}

# ── the latch ────────────────────────────────────────────────────────────────────────────────────
# One report per peer, EVER. The population is a standing pile (155 stale rows today), so a pass that
# re-reported it every five minutes would be the always-firing alarm this repo already knows carries
# exactly as many bits as one that never fires.
latch_key() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'; }
already_reported() { [ -f "$STATE/reported/$(latch_key "$1").reported" ]; }
mark_reported() {
  mkdir -p "$STATE/reported" 2>/dev/null || return 1
  printf '%s %s\n' "$(now_iso)" "$2" > "$STATE/reported/$(latch_key "$1").reported"
}

ledger_row() { # <json>
  mkdir -p "$STATE" 2>/dev/null || return 0
  printf '%s\n' "$1" >> "$LEDGER" 2>/dev/null || true
}

# ── selftest ─────────────────────────────────────────────────────────────────────────────────────
if [ "$SELFTEST" -eq 1 ]; then
  fails=0
  chk() { if [ "$2" = "$3" ]; then printf 'ok   %s\n' "$1"; else printf 'FAIL %s (got %s want %s)\n' "$1" "$2" "$3"; fails=$((fails+1)); fi; }
  PANE_OK=1; PANE_LIST=$'101\n102'
  chk "live pane is ALIVE"            "$(peer_disposition 101)"                 ALIVE
  chk "absent pane is GONE"           "$(peer_disposition 999)"                 GONE
  PANE_OK=0
  chk "blind pane oracle is UNKNOWN"  "$(peer_disposition 999)"                 UNKNOWN
  CLOUD_OK=1; CLOUD_STATES=$'session_A\tALIVE\nsession_B\tABANDONED'
  chk "cloud ALIVE"                   "$(peer_disposition cloud:session_A)"     ALIVE
  chk "cloud ABANDONED is GONE"       "$(peer_disposition cloud:session_B)"     GONE
  chk "cloud id not carried = UNKNOWN" "$(peer_disposition cloud:session_ZZZ)"  UNKNOWN
  CLOUD_OK=0
  chk "blind cloud oracle is UNKNOWN" "$(peer_disposition cloud:session_A)"     UNKNOWN
  [ "$fails" -eq 0 ] && { printf 'selftest: PASS\n'; exit 0; }
  printf 'selftest: %d FAILURE(S)\n' "$fails"; exit 1
fi

# ── the acting guard ─────────────────────────────────────────────────────────────────────────────
# This pass WRITES to the operator's live stores (cc-notify inboxes, the backlog). autonomy-sweep's
# own header records what happens when an acting rail forgets this: `postland-verify` runs the suite
# from a throwaway worktree UNDER the config dir, and every such run acted on live state for days.
# The invocation path is the discriminator and it is exact — a prefix match is defeated by the very
# harness it excludes (memory: guard-refusal-fires-on-its-own-harness). `$0` stays UNRESOLVED:
# resolving it follows the deployed symlink back into the checkout and erases the only difference.
_cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; _cfg="${_cfg%/}"
DEPLOYED=0
[ "$0" = "$_cfg/scripts/custody-deathwatch.sh" ] && DEPLOYED=1
[ "${CC_DEATHWATCH_DEPLOYED:-}" = "1" ] && DEPLOYED=1
if [ "$DEPLOYED" != 1 ] && [ "$DRY" -eq 0 ]; then
  say "custody-deathwatch: not the deployed copy ($0) — reporting is INERT here. Re-run with --dry-run to inspect."
  ledger_row "$(jq -nc --arg ts "$(now_iso)" '{ts:$ts, pass:"skipped-not-deployed"}')"
  exit 0
fi

[ -n "$CUSTODY_BIN" ] || { say "custody-deathwatch: cc-custody not found — cannot read the ledger"; exit 3; }

# ── the pass ─────────────────────────────────────────────────────────────────────────────────────
# STORE-WIDE on purpose: no `--cwd`. Every other consumer scopes to `.` and is therefore blind to the
# launchd shard keyed on `/`, which is where 175 of the 179 open debts live.
OPEN_JSON="$("$CUSTODY_BIN" list --open --json 2>/dev/null)" || OPEN_JSON=""
[ -n "$OPEN_JSON" ] || OPEN_JSON='[]'
TOTAL="$(printf '%s' "$OPEN_JSON" | jq 'length' 2>/dev/null)" || TOTAL=0

# LOAD EACH ORACLE ONLY IF THE OPEN SET ACTUALLY CONTAINS ITS KIND. The cloud oracle is a
# per-session control-plane round trip (bounded at CLOUD_TIMEOUT_S, measured rc 124 at 90 s on the
# live store), so paying it when no cloud row exists spends a minute of the sweep's budget to
# answer a question nobody asked — and on a tick where the bound bites, that cost lands on the
# LOCAL rows' latency too. Counting first is exact and free: the open set is already in hand.
_n_cloud="$(printf '%s' "$OPEN_JSON" | jq '[.[] | select((.targetPane//"") | startswith("cloud:"))] | length' 2>/dev/null)" || _n_cloud=0
_n_local="$(printf '%s' "$OPEN_JSON" | jq '[.[] | select(((.targetPane//"") | startswith("cloud:")) | not)] | length' 2>/dev/null)" || _n_local=0
# The originator-pane lookup also needs the pane oracle, so load it whenever ANY row could name one.
[ "${_n_local:-0}" -gt 0 ] || [ "$(printf '%s' "$OPEN_JSON" | jq '[.[] | select(has("originatorPane"))] | length' 2>/dev/null || echo 0)" -gt 0 ] && load_pane_oracle
[ "${_n_cloud:-0}" -gt 0 ] && load_cloud_oracle

n_alive=0; n_gone=0; n_unknown=0; n_reported=0; n_latched=0
ORPHANS=""              # marker \x1f disposition \x1f age \x1f slug \x1f target \x1f cwd
                        # US-delimited, never tab: see the @sh note at the row loop below.
DIRECT=0                # peers whose originator pane was reachable

# 🚨 ROW TRANSPORT IS `@sh` + eval, NOT a delimited read — and the delimited version SHIPPED A FALSE
# DEATH. `IFS=$'\t' read -r a b c …` looks exact, but TAB IS IFS WHITESPACE: bash strips leading
# runs of it and collapses interior runs, so ANY empty field silently shifts every later field one
# position left. Measured on the live store 2026-08-23: the one open row with a null `marker`
# (`fire-custody-integrity`) shifted its whole tuple — `target` became a cwd PATH, which is in no
# pane list, so the pass judged a session that was RUNNING AT THAT MOMENT to be GONE, and addressed
# its notification to "pane 0" (the age field). A false death over live work is the failure direction
# this file's header calls the worse one, and a tab-delimited read cannot be made safe by quoting.
# `@sh` emits shell-quoted `name=value` assignments, so an empty value stays an empty value.
while IFS= read -r _asn; do
  [ -n "$_asn" ] || continue
  marker="" slug="" target="" cwd="" opane="" age="" stale=""
  eval "$_asn"
  [ -n "$marker$slug" ] || continue
  key="${marker:-$slug}"

  disp="$(peer_disposition "$target")"
  case "$disp" in
    ALIVE)   n_alive=$((n_alive+1));   continue ;;
    GONE)    n_gone=$((n_gone+1)) ;;
    UNKNOWN) n_unknown=$((n_unknown+1))
             # The oracle-independent floor. A stale row is reported even when nothing could be
             # measured about it — this arm is what survives a six-day control-plane outage.
             [ "$stale" = "true" ] || continue ;;
  esac

  if already_reported "$key"; then n_latched=$((n_latched+1)); continue; fi

  # ADDRESS 1 — a live originator pane. The originator LEARNS, through the inbox it already reads.
  delivered=0
  if [ -n "$opane" ] && [ "$opane" != "-" ] && [ -n "$NOTIFY_BIN" ]; then
    if [ "$(peer_disposition "$opane")" = ALIVE ]; then
      msg="CUSTODY-DEATHWATCH: the peer you fired (${slug:-$marker}, target ${target:-?}) is ${disp} and has NOT returned — its custody debt has been open ${age}h. Collect+land its work, then \`cc-custody return ${key}\`; if it is superseded, \`cc-custody abandon ${key} --why …\`."
      if [ "$DRY" -eq 1 ]; then say "  would notify pane $opane about $key"; delivered=1
      elif "$NOTIFY_BIN" "$opane" "$msg" >/dev/null 2>&1; then delivered=1; DIRECT=$((DIRECT+1)); fi
    fi
  fi

  if [ "$delivered" -eq 1 ]; then
    [ "$DRY" -eq 0 ] && mark_reported "$key" "notified:$opane"
    n_reported=$((n_reported+1))
    ledger_row "$(jq -nc --arg ts "$(now_iso)" --arg k "$key" --arg d "$disp" --arg p "$opane" \
                    '{ts:$ts, marker:$k, disposition:$d, delivery:"pane", pane:$p}')"
  else
    # ADDRESS 2 — no reachable originator. Aggregate; filed once below.
    ORPHANS="${ORPHANS}${key}"$'\037'"${disp}"$'\037'"${age}h"$'\037'"${slug:--}"$'\037'"${target:--}"$'\037'"${cwd:--}"$'\n'
  fi
done <<EOF
$(printf '%s' "$OPEN_JSON" | jq -r '.[] | @sh "marker=\(.marker//"") slug=\(.slug//"") target=\(.targetPane//"") cwd=\(.cwd//"") opane=\(.originatorPane//"") age=\((.ageHours|tostring)//"?") stale=\(.stale|tostring)"')
EOF

n_orphan="$(printf '%s' "$ORPHANS" | awk 'NF{n++} END{print n+0}')"

# ── ADDRESS 2: one operator row per pass, never one per peer ─────────────────────────────────────
# 155 stale rows exist today. Filing 155 backlog rows would be the unreadable wall the ONE-COMMAND
# rule exists to prevent, so the pile collapses to a single counted row plus a manifest on disk.
if [ "$n_orphan" -gt 0 ]; then
  mkdir -p "$STATE" 2>/dev/null
  manifest="$STATE/orphans-$(date -u +%Y%m%dT%H%M%SZ).tsv"
  if [ "$DRY" -eq 1 ]; then
    say "  would file ONE backlog row for $n_orphan unreachable peer(s); manifest → $manifest"
    printf 'marker\tdisposition\tage\tslug\ttarget\tcwd\n'; printf '%s' "$ORPHANS" | tr '\037' '\t'
  else
    { printf 'marker\tdisposition\tage\tslug\ttarget\tcwd\n'; printf '%s' "$ORPHANS" | tr '\037' '\t'; } > "$manifest"
    if [ -n "$BACKLOG_BIN" ]; then
      step="$n_orphan dispatched peer(s) are gone/unreturned with custody OPEN and NO reachable originator — decide each: collect+land then \`cc-custody return <marker>\`, or \`cc-custody abandon <marker> --why …\`. Manifest: $manifest"
      "$BACKLOG_BIN" needs "$step" --run "column -t -s\$'\t' $manifest" >/dev/null 2>&1 \
        || say "custody-deathwatch: could NOT file the operator row (cc-backlog refused) — manifest still at $manifest"
    else
      say "custody-deathwatch: cc-backlog absent — manifest at $manifest, nothing filed"
    fi
    while IFS=$'\037' read -r k rest; do
      [ -n "$k" ] || continue
      mark_reported "$k" "backlog-aggregate"
    done <<ORPH
$ORPHANS
ORPH
    n_reported=$((n_reported + n_orphan))
  fi
  ledger_row "$(jq -nc --arg ts "$(now_iso)" --argjson n "$n_orphan" --arg m "$manifest" \
                  '{ts:$ts, orphans:$n, delivery:"backlog-aggregate", manifest:$m}')"
fi

say "custody-deathwatch: open=$TOTAL alive=$n_alive gone=$n_gone unknown=$n_unknown → reported=$n_reported (direct=$DIRECT, aggregated=$n_orphan) latched=$n_latched"
ledger_row "$(jq -nc --arg ts "$(now_iso)" --argjson t "${TOTAL:-0}" --argjson a "$n_alive" \
                --argjson g "$n_gone" --argjson u "$n_unknown" --argjson r "$n_reported" --argjson l "$n_latched" \
                --argjson po "$PANE_OK" --argjson co "$CLOUD_OK" \
                '{ts:$ts, pass:"complete", open:$t, alive:$a, gone:$g, unknown:$u, reported:$r, latched:$l,
                  pane_oracle_ok:($po==1), cloud_oracle_ok:($co==1)}')"
exit 0
