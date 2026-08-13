# shellcheck shell=bash
# shellcheck disable=SC2034  # file-wide: CC_ENGAGE_PROOF/_SID/_WHY are this lib's OUTPUT contract —
# set here, read by consumers (bin/cc-wedge-watch). A library's exports always look unused in it.
# engagement.sh — the ONE definition of "did a spawned Claude Code session actually run?"
#
# ── WHY THIS FILE EXISTS ─────────────────────────────────────────────────────────────────────────
# A spawned session stopped at a blocking startup modal is indistinguishable from a working agent:
# the pane is alive, the process is alive, and no hook fires — so there is no cc-registry row, no
# /tmp/cc-telemetry row and no transcript (docs/research/cc-startup-modals-2026-08-04.md §"Why this
# class matters"). Every ordinary liveness probe on this box answers "fine".
#
# `scripts/handoff-fire.sh` is the one path that already had an oracle for this, and it is proven in
# production. The startup-modal census named lifting it into a shared home as the second arm of the
# remedy — "It is the only thing in the tree that would have caught this incident" (§3). This is
# that home. `bin/cc-wedge-watch` is its first consumer.
#
# ⚠️ THE TWO "NAMED NEXT CONSUMERS" ARE BOTH REFUTED (measured 2026-08-12, backlog f76e7d78aaac).
# This header used to read "scripts/limit-recover/lr-fire-resume.sh and scripts/cc-upgrade-gate.sh,
# which have no oracle at all today, are the named next ones", and a backlog row prescribed exactly
# that wiring. Neither can host an oracle:
#   · cc-upgrade-gate.sh spawns NO pane. Every probe is `gate_headless()`
#     (lib/cc-upgrade-gate/common.sh:42-48) = `--print --output-format json`, and
#     `grep -rnE 'handoff-fire|it2|osascript|split-right' lib/cc-upgrade-gate/ scripts/cc-upgrade-gate.sh`
#     returns zero hits. A headless run mints no registry row, so cc_engaged_pane could only ever
#     answer `no-registry-row` — wiring it there would FAIL every healthy probe.
#   · lr-fire-resume.sh `exec expect`s at :385, so the spawning process BECOMES the session. There
#     is no "after the spawn" left in which to check anything.
# The real gap is the daemon that DOES survive its spawns — scripts/limit-recover/lr-reset-poller.sh
# — and it holds a SID, not a pane. That is what `cc_engaged_sid` below is for.
#
# ── WHY A COPY WITH A PARITY TEST, NOT A REFACTOR OF handoff-fire.sh ─────────────────────────────
# Six suites (tests/fire-engagement.bats, handoff-engage-scan-window, handoff-fire-pane-parked,
# handoff-lifecycle-record, handoff-recycle-engagement, handoff-selfclose) `sed`-extract
# `assistant_turn_in` / `engagement_seen` out of handoff-fire.sh as ISOLATED units — the extraction
# is their whole isolation strategy. Making handoff-fire source this file would break all six and
# put the live fire path at risk for a refactor's benefit. So `assistant_turn_in` below is a
# BYTE-IDENTICAL copy, and tests/spawn-wedge-watchdog.bats asserts that byte-for-byte against
# handoff-fire.sh on every run. Drift is therefore impossible in the only direction that matters:
# the day someone improves one copy, the gate names the other. (memory:
# make-the-actuator-the-arbiter — never let two spellings of one predicate diverge unwatched.)
#
# ── THE ORACLE IS STRUCTURAL, AND THAT IS THE POINT ──────────────────────────────────────────────
# "A content-bearing assistant turn exists in the session's transcript" is a fact about a JSONL
# record, not about pixels. It cannot drift when a footer is redesigned. That property is not
# theoretical: the census's own prescribed detector keyed on the on-screen string `? for shortcuts`,
# measured 9/9 on 2026-08-04, and four days later it was ABSENT on 23 of 23 healthy live panes
# because every one of them runs auto mode, whose footer replaces that hint. A detector shipped on
# that anchor would have paged the entire fleet on day one. See bin/cc-wedge-watch § ANCHOR.
#
# BIRTH IS NOT ENGAGEMENT (handoff-fire.sh, item ff2d6609a33e). A transcript's or a registry row's
# mere EXISTENCE proves only that something was created — attachment and system rows land, and the
# registry row is written by the SessionStart hook before the model has done anything. A fire whose
# first prompt was rejected or never submitted is born with exactly those rows and then idles
# forever. Engagement requires a real first ASSISTANT turn; every function here honours that.

# Guard against double-sourcing: consumers may source this from a hook AND from a helper.
[ -n "${CC_ENGAGEMENT_LIB_LOADED:-}" ] && return 0 2>/dev/null
CC_ENGAGEMENT_LIB_LOADED=1

# ── BEGIN parity-pinned region (byte-identical to scripts/handoff-fire.sh) ───────────────────────
# Do not reformat, rewrap or "improve" the block below. tests/spawn-wedge-watchdog.bats compares it
# byte-for-byte with `sed -n '/^assistant_turn_in() {/,/^}/p' scripts/handoff-fire.sh`. Change the
# predicate in BOTH files in ONE commit, or the gate goes red naming this file.
assistant_turn_in() { # $1=transcript jsonl → 0 a content-bearing assistant turn exists / 1 none
  local f="$1"
  [ -s "$f" ] || return 1
  if command -v jq >/dev/null 2>&1; then
    # `first(inputs|…)` short-circuits on the first hit — never slurps a large transcript.
    [ "$(jq -rn 'first(inputs
                   | select(.type == "assistant"
                            and (((.message.content? // .content? // "") | tostring | length) > 0))
                   | "1")' "$f" 2>/dev/null)" = 1 ] && return 0
    return 1
  fi
  grep -q '"type":"assistant"' "$f"   # jq-less fallback: still a turn-check, never mere existence
}
# ── END parity-pinned region ────────────────────────────────────────────────────────────────────

# cc_engagement_homes — every account home whose projects/ dir could hold the transcript, newline-
# separated, existing ones only.
#
# WHY ALL OF THEM RATHER THAN THE ROW'S OWN `account` FIELD. The cc-registry row does carry one
# (`"account": "claude-next"`), but its vocabulary is the LAUNCHER-derived name, which is not a key
# of lib/account-map.generated.sh's `cc_acct_dir_for_name` (`next`, `claude`, `next2`, …). Mapping
# it would mint a THIRD spelling of the account namespace for the sole purpose of skipping four
# `test -f` calls. Searching every home is account-agnostic and cannot be wrong; a session id is
# globally unique, so a hit in any home is THE transcript. CC_ENGAGE_HOMES overrides for tests.
cc_engagement_homes() {
  if [ -n "${CC_ENGAGE_HOMES:-}" ]; then printf '%s\n' "$CC_ENGAGE_HOMES" | tr ':' '\n'; return 0; fi
  local h
  for h in "$HOME/.claude" "$HOME/.claude-next" "$HOME/.claude-secondary" \
           "$HOME/.claude-tertiary" "$HOME/.claude-quaternary"; do
    [ -d "$h/projects" ] && printf '%s\n' "$h"
  done
}

# cc_engaged_sid — $1=session id → 0 that session took a real assistant turn / 1 it did not
#
# WHY A SID ENTRY POINT EXISTS AT ALL. `cc_engaged_pane` is keyed on a PANE, and every caller that
# holds a pane id is terminal-side. `scripts/limit-recover/lr-reset-poller.sh` — a long-running
# daemon that DOES survive its spawns, unlike lr-fire-resume.sh which `exec expect`s and BECOMES the
# session — holds only a SESSION ID: it writes `$CLAIMS/<sid>` before the launcher→expect→claude
# chain exists, precisely because no pane and no registry row exist yet. The pane oracle was
# therefore structurally unreachable from the one place in limit-recovery that could use it, and
# that key mismatch is the whole reason this class was never wired there.
#
# EXTRACTED, NOT RE-SPELLED. `cc_engaged_pane` below now calls this function for the second half of
# its own path; the search exists exactly once in this file. Two spellings of one predicate diverge
# the day someone improves one of them (memory: make-the-actuator-the-arbiter).
#
# Same output contract as cc_engaged_pane (CC_ENGAGE_PROOF / CC_ENGAGE_SID / CC_ENGAGE_WHY on every
# path). WHY values here: `no-session-id` · `transcript-without-assistant-turn` · `assistant-turn`.
# The latter two are byte-identical to the pane path's strings on purpose — cc-wedge-watch prints
# CC_ENGAGE_WHY as a parseable token and must not have to know which key produced the answer.
#
# PROOF is `transcript:<sid>` here and the pane path overwrites it with `registry:<sid>`, because
# the two answers were reached through different evidence and a proof token that lies about its
# provenance is worse than none.
cc_engaged_sid() {
  local sid="${1:-}" home t f
  CC_ENGAGE_PROOF="" CC_ENGAGE_SID="" CC_ENGAGE_WHY=""

  if [ -z "$sid" ]; then
    # An empty sid is a caller with nothing to ask about — reported as not-engaged WITH the reason,
    # never as a positive. `find -name ".jsonl"` would otherwise search every home for nothing.
    CC_ENGAGE_WHY="no-session-id"
    return 1
  fi
  CC_ENGAGE_SID="$sid"

  while IFS= read -r home; do
    [ -n "$home" ] || continue
    t="$home/projects"
    # The transcript lives under a cwd-slug subdir whose spelling this function has no business
    # reconstructing; `find` on the sid filename is exact and cheap (the sid IS the filename).
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if assistant_turn_in "$f"; then
        CC_ENGAGE_PROOF="transcript:$sid"
        CC_ENGAGE_WHY="assistant-turn"
        return 0
      fi
    done <<EOF
$(find "$t" -name "$sid.jsonl" -type f 2>/dev/null)
EOF
  done <<EOF
$(cc_engagement_homes)
EOF

  # A session id, but no assistant turn anywhere: the session exists and has done nothing. This is
  # the ff2d6609a33e state — precisely the one a birth-check calls healthy.
  CC_ENGAGE_WHY="transcript-without-assistant-turn"
  return 1
}

# cc_engaged_pane — $1=pane id (kitty window id / paneUUID), $2=registry dir (optional)
#   → 0 the session in that pane took a real assistant turn / 1 it did not
#
# Path: registry row → .session_id → <sid>.jsonl under any account home → assistant_turn_in.
# This is `engagement_seen`'s path (b), the one that needs no launch marker — a caller that did not
# MINT the prompt (cc-pane-runner only transports it) has no marker to grep for.
#
# Sets CC_ENGAGE_PROOF to the oracle that produced a positive, and CC_ENGAGE_SID / CC_ENGAGE_WHY on
# every path, so a caller never has to re-derive WHY it got the answer it got (memory:
# claimed-outcome-vs-checked-outcome — emit a token the consumer can parse, not a bare status).
cc_engaged_pane() {
  local pane="$1" regdir="${2:-${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}}" row sid
  CC_ENGAGE_PROOF="" CC_ENGAGE_SID="" CC_ENGAGE_WHY=""

  row="$regdir/$pane.json"
  if [ ! -f "$row" ]; then
    # NO ROW IS THE MODAL'S OWN SIGNATURE, not an instrument failure. SessionStart never fires
    # behind a blocking dialog, so the row that would name the transcript is exactly what is
    # missing. Reported as not-engaged WITH the reason, never as "cannot tell".
    CC_ENGAGE_WHY="no-registry-row"
    return 1
  fi

  if command -v jq >/dev/null 2>&1; then
    sid="$(jq -r '.session_id // empty' "$row" 2>/dev/null)"
  else
    sid="$(sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$row" | head -1)"
  fi
  if [ -z "$sid" ]; then
    # A row with no session_id is a pane registered before its session identified itself. Birth,
    # not engagement — the distinction this whole file exists to keep.
    CC_ENGAGE_WHY="row-without-session-id"
    return 1
  fi
  # The rest of the path is key-agnostic — it is `cc_engaged_sid` above, which sets CC_ENGAGE_SID
  # and CC_ENGAGE_WHY for us. Only the PROOF differs: this caller reached the sid through a
  # registry row, so it names that evidence rather than the transcript it shares with the sid path.
  # A failure leaves `transcript-without-assistant-turn` untouched — byte-identical to the string
  # this function set inline before the extraction, which cc-wedge-watch and its suite both parse.
  if cc_engaged_sid "$sid"; then
    CC_ENGAGE_PROOF="registry:$sid"
    return 0
  fi
  return 1
}
