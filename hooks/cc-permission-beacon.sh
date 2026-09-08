#!/bin/bash
# cc-permission-beacon.sh — the PermissionRequest BEACON for lead-supervisor.sh (desk-anti-hitl §B2).
#
# WHY: an UNATTENDED autonomous session that hits a permission prompt HANGS until a human answers
# (the 133-min `git reset --hard` incident, desk-anti-hitl-2026-07-19.md §B). Nothing IN-session can
# answer the prompt, and the out-of-session supervisor is STRUCTURALLY blind to modal/permission
# dialogs (lead-supervisor.sh S-3 — a bash sweep cannot read a modal). Today that block only surfaces
# ~30 min later as a generic STALL?/MODAL page with no detail; resolution took 2h13m.
#
# THIS beacon makes the block VISIBLE, ATTRIBUTED, and FAST: on a permission prompt the HARNESS (not a
# worker) writes an unspoofable record {ts, tool_name, tool_input, cwd, tool_use_id} to
# CC_PERMPEND_DIR/<sid>.json.
# lead-supervisor.sh's sweep reads the dir and pages "PERMISSION-PENDING: <cmd> since <ts>" within
# minutes, with the exact blocked command attached — a precise escalation instead of a silent hang.
#
# CONTRACT (mode = $1, from the hook wiring):
#   write  — PermissionRequest event: the harness is showing a permission prompt ⇒ persist the beacon.
#   clear  — PostToolUse | Stop | SessionEnd: the prompt is RESOLVED ⇒ remove the beacon.
#
# WHY THE CLEARS ARE COMPLETE (no missed-clear leak, and no dependence on a PermissionDenied event —
# this harness has none):
#   • A permission prompt is ALWAYS mid-turn — the turn cannot Stop until the human answers. So the
#     turn's Stop fires after EVERY resolution, GRANT or DENY, guaranteeing a clear even on the deny
#     path (which never runs PostToolUse). Stop is the universal clearer.
#   • PostToolUse is the FASTER clear on the grant path (fires the instant the tool runs, before the
#     turn ends), narrowing the stale window.
#   • SessionEnd is the backstop for a session that closes without a Stop.
#   • A hard-killed session (kill -9 / OOM, no SessionEnd) cannot strand a forever-pending beacon:
#     the supervisor independently REAPS a beacon whose owning session is provably dead (pid gone via
#     telemetry) and any beacon past a long orphan horizon.
#
# SAFETY: the payload is HARNESS-AUTHORED (session_id/tool_name/tool_input/cwd arrive on the hook's
# stdin from the harness, NOT worker-influenced content) ⇒ unspoofable. This hook is a pure OBSERVER:
# it emits NO permission decision, so the prompt proceeds exactly as before. Fail-open + fail-quiet:
# any parse/IO error exits 0 with no decision and no partial file.
#
# Kill switch: CC_PERMISSION_BEACON_DISABLED=1  (no-op, both modes).
# Seams: CC_PERMPEND_DIR (default /tmp/cc-permission-pending) — MUST match lead-supervisor.sh; E2E
#        isolation. CC_PERMARCHIVE_DIR / CC_PERMARCHIVE_MAXLEN — the durable archive (see `archive`).

[[ "${CC_PERMISSION_BEACON_DISABLED:-0}" == "1" ]] && exit 0
set -uo pipefail

MODE="${1:-}"
DIR="${CC_PERMPEND_DIR:-/tmp/cc-permission-pending}"
# Durable ARCHIVE (see the `archive` function below). Deliberately NOT under CC_PERMPEND_DIR:
# that lives in /tmp and is wiped on reboot, and the whole point of the archive is a record that
# outlives the box's uptime so the classifier can be tuned on weeks of real data.
# ${HOME:-} — NOT bare $HOME. `set -u` is on, and this line sits ABOVE the mode dispatch, so an
# unset HOME aborted the ENTIRE hook at rc=1: `write` never ran, no beacon was created, and the
# supervisor went blind to a real pending prompt. An archive convenience must never be able to
# take down the beacon it is a side-car to (regression caught in adversarial review, 2026-07-31).
ARCHDIR="${CC_PERMARCHIVE_DIR:-${HOME:-/tmp}/.claude/autonomy/permission-archive}"
ARCH_MAXLEN="${CC_PERMARCHIVE_MAXLEN:-3500}"

# Read the harness payload once (fail-open on empty/malformed — never block the prompt).
INPUT="$(cat 2>/dev/null || true)"
SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
[[ -z "$SID" ]] && exit 0                       # no session id ⇒ nothing to key a beacon on
# Defense-in-depth: a session id is a uuid; reject anything that isn't a safe basename so the
# path can never escape DIR (harness sids are already clean — this is belt-and-suspenders).
case "$SID" in *[!A-Za-z0-9._-]*|''|.|..) exit 0 ;; esac

BEACON="$DIR/$SID.json"

# ── EXISTENCE EVIDENCE / positive control (cc-backlog 1e16815bac51) ──────────────────────────────
# WHY: an EMPTY beacon dir and a beacon that has NEVER RUN are the SAME observation — absence — and
# only one of them is good news. This hook shipped landed-but-registered-nowhere, so
# /tmp/cc-permission-pending/ was never created; "no pending approvals" actually meant "the hook has
# never fired once" and NOTHING could tell the two apart. A teammate sat blocked on an approval its
# (dead) lead could never answer while the board reported all-clear (2026-07-29; memory
# absence-alarm-needs-existence-evidence — an absence alarm needs evidence its producer's world exists).
#
# The heartbeat is the liveness half of that control: EVERY invocation — write AND clear — creates
# the dir and stamps this file, so after the first hook call of any session the dir exists even when
# nothing is ever pending. Consumers then read a THREE-state world instead of a two-state one:
#   dir ABSENT                      ⇒ the hook has never run (INERT — wired wrong, or not at all)
#   dir present, no <sid>.json      ⇒ genuinely nothing pending  (the all-clear that can be trusted)
#   dir present, <sid>.json present ⇒ a real pending prompt
# cc-blockers' `beacon-inert` alarm renders exactly that split; the wiring half (registered in no
# settings.json) it reads statically, because an unregistered hook cannot heartbeat either.
#
# COST: `clear` runs on every PostToolUse, so this stays FORK-FREE on the hot path — a builtin
# [[ -d ]] test (so mkdir forks once per boot, not once per tool call) and a `:` truncate whose
# MTIME *is* the timestamp, so no date(1) fork. Dot-prefixed and suffix-less so it can never be read
# as a beacon: lead-supervisor globs "$dir"/*.json, which matches neither a dotfile nor this name.
HEARTBEAT="$DIR/.beacon-alive"
beat() {
  [[ -d "$DIR" ]] || mkdir -p "$DIR" 2>/dev/null || return 0
  : > "$HEARTBEAT" 2>/dev/null || true
}

# The ARCHIVE needs the same control, and shipped without it — which INVERTED the three states the
# consumer reports. ARCHDIR was created only inside archive(), immediately before an append, so:
# a wired, running archiver that has simply had no prompts to record leaves NO directory and was
# reported "BLIND — has never archived", while "present but empty" — the branch asserting "wired and
# running" — was unreachable by the archiver's own path and could arise only from deletion or a read
# error. The strongest claim rested on the weakest evidence, exactly the failure the split exists to
# prevent. Stamping on EVERY clear makes dir-exists mean "the archiver ran", for real.
ARCH_HEARTBEAT="$ARCHDIR/.archive-alive"
arch_beat() {
  [[ -d "$ARCHDIR" ]] || mkdir -p "$ARCHDIR" 2>/dev/null || return 0
  : > "$ARCH_HEARTBEAT" 2>/dev/null || true
}

# ── DURABLE ARCHIVE (§3 Stage A.4) ───────────────────────────────────────────────────────────────
# WHY: `clear` used to `rm -f` each record the moment it was answered, so NO history of actual
# permission prompts existed anywhere on this box. Two consequences, both measured:
#   • bin/cc-permission-audit can only ever report an UPPER bound — it infers candidates from
#     transcripts against the static rules, and cannot see what auto mode's classifier silently
#     approved or additionally raised. Its own docstring says so.
#   • The classifier therefore can never be tuned on real data, which is Step 3's named guardrail.
# So the record is appended to a durable append-only JSONL before it is removed.
#
# `resolved_by` + the INVOCATION SIGNATURE (`tool_sig`/`cleared_tool_sig`) are the load-bearing
# fields for that tuning. The tempting shortcut — "PostToolUse only fires on the grant path, so
# PostToolUse means approved" — is FALSE: PostToolUse fires for every tool, not only the prompted
# one, so after a DENIAL the turn can continue, run some other tool, and have THAT tool's
# PostToolUse clear this still-pending beacon, archiving the refusal as an approval. Comparing tool
# NAMES does not rescue it either: this fleet's traffic is overwhelmingly Bash, so a denied
# `git push --force` cleared by a later `git status` matches on name and is still wrong. Only the
# specific INVOCATION can prove a grant; see `archive`. None of these fields is recoverable from
# anywhere else after the fact.
#
# ATOMICITY: many sessions append to one file concurrently. A single small write(2) under O_APPEND
# does not interleave, so the record is length-BOUNDED (ARCH_MAXLEN, default 3500 B — comfortably
# inside the 4 KiB atomic-append regime) and over-long payloads degrade to a truncated summary
# rather than risking a torn line. Truncation is RECORDED (`tool_input_truncated`), never silent.
#
# THE INVOCATION, not the tool NAME, is what can prove a grant. Name-matching was the first cut and
# it is a guess that fails in the unsafe direction: the dominant traffic here is Bash→Bash, so a
# DENIED `git push --force` followed by any other Bash command in the same turn yields
# cleared_tool == tool_name == "Bash", and the refusal is recorded as an approval.
#
# 🚨 THE SECOND CUT — `tool_use_id` — WAS DEAD ON ARRIVAL, and it looked healthy for five weeks.
# It reads the id of the prompted invocation off the PermissionRequest payload and matches it
# against PostToolUse's. PostToolUse's half is populated (3,650 of 3,757 archived rows). The
# PermissionRequest half is ALWAYS the empty string — 0 of 3,641 archived records and 0 in the live
# payload captured 2026-09-06 (docs/plans/HOOK_SURFACE_100P.md § 3a row 16). `tid and cid` therefore
# never held, the rule never once fired, and the consumer silently fell through to the tool-NAME
# path this comment block exists to reject: bin/cc-permission-audit read `approved 0 · unknown 3359`
# over 3,763 real prompts and that zero was an artifact of the instrument, not a fact about grants.
# The id exists in the world — the transcript's own `tool_use` block carries `toolu_…`, and
# PreToolUse/PostToolUse both ship it — it is simply absent from THIS event.
#
# What IS populated on both events is the invocation itself: `tool_name` + `tool_input`. Measured
# 2026-09-07 against five archived prompts and their sessions' transcripts, the `tool_input` this
# beacon stores from PermissionRequest is key-for-key and value-for-value the same object as the
# transcript's `tool_use.input`, which is what PostToolUse also carries. So the discriminator is the
# SIGNATURE of the invocation — sha256 over the canonical (recursively key-sorted) form of
# {tool_name, tool_input}, stored as `tool_sig` (prompt side) and `cleared_tool_sig` (clearing side).
# Equal signatures mean the very invocation that was gated is the one that ran.
#
# RESIDUAL, stated rather than hidden: a signature is not an id, so a false approval is conceivable
# — it needs a SECOND invocation with the same tool AND byte-identical input to clear the beacon in
# the same turn. A denied command re-run identically re-prompts, which overwrites the beacon, so
# the surviving record is the newer prompt; that is what makes the path narrow rather than routine.
# Every other way it can fail lands on `collateral`/`unknown`, i.e. the safe direction. A signature
# is emitted only when `tool_name` is non-empty, so two unparseable payloads can never digest to the
# same empty canonical form and read as a match — the failure mode a naive `printf | shasum` has.
# `tool_use_id`/`cleared_tool_use_id` are still recorded and the consumer still PREFERS an id match
# when both are present: if a later binary starts populating the field, the stronger rule takes over
# with no change here, and until then the archive is the standing evidence that it does not.
# Absence of both is reported as UNKNOWN, never approved — a split that is honestly empty beats one
# that is confidently wrong.
# The canonical form of an invocation, identical on both events. `jq -S` sorts object keys
# RECURSIVELY on output, so two payloads that differ only in key order digest the same. The guard
# is the load-bearing half: `empty` when tool_name is absent means an unparseable or non-tool
# payload produces NO canonical form at all, so it can never be digested into a value that matches
# another unparseable payload. Without it, two failures would both hash the empty string and be
# read as proof of a grant — a false approval manufactured out of two errors.
CANON='if (.tool_name // "") == "" then empty else {n:.tool_name, i:(.tool_input // {})} end'

sig_of() { # $1 = a canonical line (possibly empty) → 16 hex chars, or nothing at all
  local canon="$1" h
  [[ -z "$canon" ]] && return 0
  h="$(printf '%s' "$canon" | shasum -a 256 2>/dev/null)" || return 0
  h="${h%% *}"
  [[ "$h" =~ ^[0-9a-f]{64}$ ]] || return 0        # a truncated/failed digest is NOT a signature
  printf '%s' "${h:0:16}"
}

archive() { # $1 = the CLAIMED beacon, already moved aside so no second clear can archive it too
  local claimed="$1" rts mon line
  mkdir -p "$ARCHDIR" 2>/dev/null || return 0
  # One date(1) fork for both the timestamp and the month bucket.
  local d; d="$(date +'%s %Y-%m' 2>/dev/null)" || return 0
  rts="${d%% *}"; mon="${d##* }"
  # BOTH fields in one jq fork. `cleared_tool` is what makes the outcome inferable at all:
  # PostToolUse fires for EVERY tool, not only the prompted one. After a DENIAL the turn can
  # continue and run some other tool, whose PostToolUse then clears this still-pending beacon —
  # so `resolved_by == PostToolUse` alone would silently record that denial as an approval.
  # Comparing cleared_tool against the beacon's own tool_name separates a real grant from such a
  # collateral clear; the consumer treats a mismatch as UNKNOWN rather than guessing either way.
  local by ct cid _bi
  _bi="$(printf '%s' "$INPUT" | jq -r '[(.hook_event_name // ""), (.tool_name // ""), (.tool_use_id // "")] | join("\u001f")' 2>/dev/null || true)"
  IFS=$'\x1f' read -r by ct cid <<<"$_bi" || true

  # The two signatures. Costs two jq + two shasum forks, but ONLY on a real resolution — the `mv`
  # claim above has already failed and exited for every PostToolUse with nothing pending, so the hot
  # path never reaches here. Measured traffic: ~3.8k resolutions in five weeks.
  local sig_b sig_c
  sig_b="$(sig_of "$(jq -Sc "$CANON" "$claimed" 2>/dev/null || true)")"
  sig_c="$(sig_of "$(printf '%s' "$INPUT" | jq -Sc "$CANON" 2>/dev/null || true)")"

  line="$(jq -c --arg sid "$SID" --arg by "${by:-unknown}" --arg ct "$ct" --arg cid "$cid" \
      --arg sb "$sig_b" --arg sc "$sig_c" \
      --argjson rts "$rts" \
      '{session_id:$sid, ts:(.ts//$rts), resolved_ts:$rts, waited_s:($rts - (.ts//$rts)),
        resolved_by:$by, cleared_tool:$ct, cleared_tool_use_id:$cid,
        tool_sig:$sb, cleared_tool_sig:$sc,
        tool_use_id:(.tool_use_id//""), tool_name:(.tool_name//""),
        tool_input:(.tool_input//{}), cwd:(.cwd//"")}' "$claimed" 2>/dev/null)" || return 0
  [[ -z "$line" ]] && return 0

  # BYTES, not characters. ${#line} counts CHARACTERS, so 3,000 CJK characters measured 3,215
  # against the cap while occupying 9,215 bytes — 2.25x the regime the atomicity argument relies
  # on, with truncation never firing. LC_ALL=C makes the bound the same unit as the guarantee.
  local nbytes; nbytes="$(LC_ALL=C; printf %s "$line" | wc -c)"; nbytes="${nbytes// /}"
  if (( nbytes > ARCH_MAXLEN )); then
    line="$(jq -c --arg sid "$SID" --arg by "${by:-unknown}" --argjson rts "$rts" \
        --arg sb "$sig_b" --arg sc "$sig_c" \
        --argjson cap "$((ARCH_MAXLEN / 2))" \
        '{session_id:$sid, ts:(.ts//$rts), resolved_ts:$rts, waited_s:($rts - (.ts//$rts)),
          resolved_by:$by, tool_name:(.tool_name//""), cwd:(.cwd//""),
          tool_sig:$sb, cleared_tool_sig:$sc,
          tool_input_truncated:true,
          tool_input_summary:((.tool_input//{}|tostring)[0:$cap])}' "$claimed" 2>/dev/null)" || return 0
    [[ -z "$line" ]] && return 0
    # RE-MEASURE. The truncated form is bounded in CHARACTERS too, so a multibyte payload could
    # still land over the byte cap after "truncation" — the fallback inheriting the exact bug it
    # was meant to fix. If it is still over, drop tool_input entirely: identity, timing and
    # attribution are what the archive is FOR, and they always fit.
    nbytes="$(LC_ALL=C; printf %s "$line" | wc -c)"; nbytes="${nbytes// /}"
    if (( nbytes > ARCH_MAXLEN )); then
      line="$(jq -c --arg sid "$SID" --arg by "${by:-unknown}" --arg ct "$ct" --arg cid "$cid" \
          --arg sb "$sig_b" --arg sc "$sig_c" \
          --argjson rts "$rts" \
          '{session_id:$sid, ts:(.ts//$rts), resolved_ts:$rts, waited_s:($rts - (.ts//$rts)),
            resolved_by:$by, cleared_tool:$ct, cleared_tool_use_id:$cid,
            tool_sig:$sb, cleared_tool_sig:$sc,
            tool_use_id:(.tool_use_id//""), tool_name:(.tool_name//""), cwd:(.cwd//""),
            tool_input_truncated:true, tool_input_summary:"<omitted: over byte cap>"}' \
          "$claimed" 2>/dev/null)" || return 1
      [[ -z "$line" ]] && return 1
    fi
  fi
  # SERIALIZED APPEND. "a single small write(2) under O_APPEND does not interleave" was measured
  # FALSE for this workload: 120-way concurrency at ~1.2 KB rows tore 10 of 720 lines, merging two
  # sessions' records into one unparseable line — under BOTH the 3500 B cap and the 4 KiB page. The
  # corrupt counts were always EVEN (A-chunk, B-whole, A-chunk), i.e. split-write interleaving, and
  # the threshold is offset-dependent rather than a flat size rule, so no cap can be trusted to
  # avoid it. mkdir is atomic on every POSIX filesystem and macOS ships no flock(1), so it is the
  # mutex. This costs forks ONLY on a real resolution, never on the PostToolUse hot path.
  local lock="$ARCHDIR/.append.lock" got=0 i=0
  while (( i < 50 )); do
    if mkdir "$lock" 2>/dev/null; then got=1; break; fi
    sleep 0.02; i=$(( i + 1 ))
  done
  if (( got )); then
    printf '%s\n' "$line" >> "$ARCHDIR/$mon.jsonl" 2>/dev/null || got=2
    rmdir "$lock" 2>/dev/null || true
  fi
  # NEVER LOSE THE RECORD. The caller rm's the claim unconditionally, so a failed append used to
  # destroy the very evidence this archive exists to keep (measured: unwritable ARCHDIR ⇒ rc=0,
  # beacon deleted, zero rows). A contended lock or a failed write now falls back to a per-process
  # sidecar — same *.jsonl glob the consumer already reads, so the row is still counted, just in its
  # own file. stderr is swallowed: bash reports a redirect failure before 2>/dev/null can apply, and
  # a hook that chatters on stderr is not fail-QUIET.
  if (( got != 1 )); then
    { printf '%s\n' "$line" >> "$ARCHDIR/$mon.$SID.$$.jsonl"; } 2>/dev/null || return 1
  fi
  return 0
}

case "$MODE" in
  clear)
    beat
    arch_beat
    # ATOMIC CLAIM. `[[ -f ]]` then archive then rm has NO mutual exclusion: two overlapping clears
    # (a trailing PostToolUse racing the turn's Stop) both passed the test and both appended, so ONE
    # prompt produced TWO rows — measured 40/40 — landing in BOTH buckets at once and inflating the
    # ranking from a single event. `mv` is atomic within a filesystem and can succeed exactly once,
    # so the winner archives and the loser silently finds nothing, which is the correct outcome for
    # a beacon that is already resolved. The claim file is dot-prefixed and suffix-less so the
    # supervisor's "$dir"/*.json glob can never read it as a pending prompt.
    CLAIM="$DIR/.claimed-$SID.$$"
    mv "$BEACON" "$CLAIM" 2>/dev/null || exit 0
    # Keep the claim when archiving FAILED — deleting it would destroy the record. It is
    # dot-prefixed, so it is invisible to the supervisor's *.json glob and cannot re-page.
    if archive "$CLAIM"; then rm -f "$CLAIM" 2>/dev/null || true; fi
    exit 0
    ;;
  write)
    mkdir -p "$DIR" 2>/dev/null || exit 0
    beat
    TS="$(date +%s)"
    # Atomic write (temp in the SAME dir + mv) so the supervisor never reads a half-written beacon.
    TMP="$(mktemp "$DIR/.$SID.XXXXXX" 2>/dev/null)" || exit 0
    if printf '%s' "$INPUT" | jq -c \
         --argjson ts "$TS" \
         '{ts:$ts, tool_name:(.tool_name // ""), tool_input:(.tool_input // {}), cwd:(.cwd // ""),
           tool_use_id:(.tool_use_id // "")}' \
         > "$TMP" 2>/dev/null; then
      mv -f "$TMP" "$BEACON" 2>/dev/null || rm -f "$TMP" 2>/dev/null || true
    else
      rm -f "$TMP" 2>/dev/null || true         # never leave a partial/garbage beacon behind
    fi
    exit 0
    ;;
  *)
    exit 0                                       # unknown/absent mode ⇒ no-op (fail-quiet)
    ;;
esac
