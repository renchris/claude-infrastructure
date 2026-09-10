#!/bin/bash
# PreToolUse hook for Bash command validation
#
# Complements settings.json deny/ask permissions with pattern-matching that
# permission prefixes can't catch (DDL inside commands, compound command
# escape hatches, bypass-flag detection aware of quoted message bodies).
#
# Exit 0 with JSON to stdout for decisions. Exit 2 for blocking errors.
#
# Rollback knobs (env):
#   VALIDATE_BASH_LEGACY=1       Use regex-only flag detection (skips shlex).
#   VALIDATE_BASH_DISABLED=1     No-op the hook entirely (emergency only).

# Kill switch
if [[ "${VALIDATE_BASH_DISABLED:-0}" == "1" ]]; then
  exit 0
fi

# Builtin read, NOT `$(cat)`: command substitution forks AND execs /bin/cat on the hottest path
# in the system (this hook fires on EVERY Bash tool call). Measured 2026-07-31: ~6 ms per hook,
# ~18% of the 163 ms PreToolUse/Bash chain across the five hooks that did this. `read -d ''`
# returns non-zero at EOF -- the normal case here -- hence `|| true`; it also PRESERVES the
# trailing newline that `$(cat)` strips, so strip it back off for byte-parity with the old value.
IFS= read -r -d '' INPUT || true
while [ "${INPUT%$'\n'}" != "${INPUT}" ]; do INPUT="${INPUT%$'\n'}"; done

# === JQ / PAYLOAD GUARD — fail OPEN, but never SILENTLY (audit 09 D-4) ===
# Every other PreToolUse hook guards jq (backup-before-write.sh:17, git-worktree-guard.sh,
# check-edit-boundary.sh, agent-teams-enforce.sh, frontier-spawn-gate.sh,
# cc-unattended-ask-guard.sh, plan-agent-teams-default.sh). This one did not: with jq absent or
# the payload unparseable, CMD went empty, EVERY danger pattern missed, and the hook exited 0 —
# the bash validator silently disabled itself. Fail-open is the right availability posture for a
# gate that can block a tool call; failing open with ZERO signal is the defect. So: still exit 0,
# but leave one loud line behind (the keychain-guard.sh:19-21 documented-fail-open posture).
# Sink + TSV shape (ts \t kind \t detail) are shared with lib/is-true-flag.sh:200-205, which
# already logs its own "could not decide" case there — one file, one shape, one meaning:
# "the bash validator did not actually validate this".
abstain_unclear() { # <reason>
  mkdir -p "$HOME/.claude/logs" 2>/dev/null || true
  printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ 2>/dev/null || echo '?')" \
    'validate-bash-ABSTAIN' "fail-open, command NOT validated: $1" \
    >> "$HOME/.claude/logs/validate-bash-unclear.log" 2>/dev/null || true
  exit 0
}
command -v jq >/dev/null 2>&1 || abstain_unclear "jq unavailable on PATH"

# ONE parse of the payload, not three (fork census 2026-08-17, backlog 054499f0c342). This hook read
# the SAME stdin three times with three `jq` execs — `.tool_input.command` here, then
# `.tool_input.run_in_background` at the /goal guard, then `.session_id` at the audit logger — for
# 11.6 ms of a 71.9 ms modal path, two thirds of it pure duplication. The same defect the plan's
# §2 audit already named in `waiting-recycle.sh` and left unfixed here.
#
# SHAPE, and it is chosen so the COMMAND cannot be corrupted: line 1 is the three scalars, tab
# separated; everything after the first newline is the command VERBATIM, newlines, tabs and all.
# `@tsv` is deliberately NOT used — it escapes a tab as `\t`, which would silently rewrite any
# command containing one, and this value is the thing every danger pattern is matched against.
# Cells are padded at the EMITTER via `cell()`, because `//` substitutes for null/false and never
# for a present-but-empty string — and tab is IFS-whitespace, so one empty cell would shift every
# later column left, silently, exit 0 (scripts/tsv-pad-lint.sh).
#
# Fail-open posture is UNCHANGED: any jq failure still lands in abstain_unclear, which is the guard
# that stops an unreadable payload from silently disabling the whole bash validator.
if ! _PAYLOAD=$(printf '%s' "$INPUT" | jq -r '
      def cell(ph): (if . == null then "" else . end) | tostring
                    | gsub("[\\t\\r\\n]"; " ") | if . == "" then ph else . end;
      ((.session_id | cell("-")) + "\t"
        + (.tool_input.run_in_background | cell("false")) + "\t"
        + (now | todateiso8601)),
      (.tool_input.command // empty)' 2>/dev/null); then
  abstain_unclear "unparseable PreToolUse payload on stdin"
fi
_META=${_PAYLOAD%%$'\n'*}
if [[ "$_PAYLOAD" == *$'\n'* ]]; then CMD=${_PAYLOAD#*$'\n'}; else CMD=""; fi
IFS=$'\t' read -r _P_SID _P_BG _P_TS <<<"$_META"
[ -n "${_P_SID:-}" ] || _P_SID="-"
[ -n "${_P_BG:-}" ] || _P_BG="false"

# Source the argv-aware flag detector. If unavailable, caller can force
# legacy mode; otherwise fall back silently on a per-call basis below.
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
if [[ -f "$LIB_DIR/is-true-flag.sh" && "${VALIDATE_BASH_LEGACY:-0}" != "1" ]]; then
  # shellcheck source=lib/is-true-flag.sh
  # shellcheck disable=SC1091  # resolved at RUNTIME from BASH_SOURCE; the static path is only
  #                              valid when shellcheck is run from hooks/ (the land gate is not)
  source "$LIB_DIR/is-true-flag.sh"
  HAVE_IS_TRUE_FLAG=1
else
  HAVE_IS_TRUE_FLAG=0
fi

# json_escape — a decision is only enforced if the harness can PARSE it. Every reason below used
# to be interpolated raw into the JSON body, so the first message to contain a `"` (or a quote
# echoed back from the user's own command, as the pkill clause does) emitted malformed JSON and the
# deny silently became a no-op — a guard that reports blocking while not blocking. Escape order is
# load-bearing: backslashes BEFORE quotes, else the added backslashes get re-escaped. Control
# characters are stripped: a literal newline is not legal inside a JSON string.
json_escape() {  # <string> → a safe JSON string BODY (no surrounding quotes)
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\000-\037'
}

# log_decision <deny|ask> <reason> — ONE JSONL line per decision this hook actually makes.
#
# WHY. `bash-commands.log` at the tail of this file is written AFTER every deny()/warn() has
# already exited, so the audit corpus contains, by construction, nothing this hook ever refused
# (PERMISSION_HARVEST §10 B1-3: a positive control found 0 `sudo rm` records in 194,535). The
# permission archive therefore records a prompt with no way to attribute it, and 80% of what read
# as a missing allow RULE was a HOOK raising an ask (§10 B2-1). Without this join key every count
# in the harvester's "rule gap" bucket re-inflates by that share. curl-gate.py's AUDIT_LOG is the
# shape being mirrored — one JSON object per line, decision + reason + session.
#
# NO FORK ON THE MODAL PATH. This runs only from deny()/warn(), i.e. only when a decision has
# already been made, which the fork census measured as the rare path; the modal Bash call reaches
# neither helper and pays nothing. The one `date` fork lives here rather than hoisted for exactly
# that reason — hoisting it would move the cost onto every call (bash 3.2 has no `%(%s)T`).
#
# FAIL-OPEN, ALWAYS. The decision below is the hook's whole job; an unwritable log may cost a
# journal line and may never cost a refusal, so every step is guarded and the function cannot
# return non-zero.
# THE 200 IS A BYTE BOUND, AND THE TRIM BELOW IS WHY THAT IS SAFE. `${x:0:200}` slices CHARACTERS
# under a UTF-8 LANG and BYTES under C, so the slice is taken in an LC_ALL=C subshell — same answer
# either way (MEMORY.md c-locale-turns-character-ops-into-byte-ops). Every reason is written in this
# repo's house style and carries em-dashes, so the cut lands mid-sequence roughly one time in
# three — and a lone continuation byte inside a JSON string makes the LINE unparseable, which for
# a journal read by `jq` per line is not a truncated label, it is a DELETED record whose loss is
# silent (parse-failures-are-verdicts-not-noise). `iconv -f UTF-8 -t UTF-8` is the validity oracle;
# it exits 0 on the first try in the common case, and the loop can never run more than 3 times
# because a UTF-8 sequence is at most 4 bytes.
log_decision() { # <decision> <reason>
  local _f="${CC_VB_DECISION_LOG:-$HOME/.claude/logs/validate-bash-decisions.jsonl}"
  local _d="${_f%/*}"
  [ "$_d" != "$_f" ] || _d=.
  [ -d "$_d" ] || mkdir -p "$_d" 2>/dev/null || return 0
  local _r _n=0; _r="$(LC_ALL=C; _s="$2"; printf '%s' "${_s:0:200}")"
  while [ -n "$_r" ] && [ "$_n" -lt 4 ] && ! printf '%s' "$_r" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1; do
    _r="${_r%?}"; _n=$((_n + 1))
  done
  printf '{"ts":%s,"sid":"%s","decision":"%s","reason":"%s"}\n' \
    "$(date -u +%s 2>/dev/null || echo 0)" \
    "$(json_escape "${_P_SID:--}")" "$1" "$(json_escape "$_r")" \
    >> "$_f" 2>/dev/null || true
  return 0
}

deny() {
  log_decision deny "$1"
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "$(json_escape "$1")"
  }
}
EOF
  exit 0
}

warn() {
  log_decision ask "$1"
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "$(json_escape "$1")"
  }
}
EOF
  exit 0
}

# check_real_flag <flag> — returns 0 if CMD contains <flag> as a real argv
# token (in a non-inert head, outside message bodies). Returns 1 otherwise.
# Falls back to word-boundary regex when the shlex helper is unavailable.
check_real_flag() {
  local flag="$1"
  if [[ "$HAVE_IS_TRUE_FLAG" == "1" ]]; then
    is_true_flag "$flag" "$CMD"
    local rc=$?
    # rc=0 → real flag; rc=1 → substring only; rc=2 → unclear (fail safe = block)
    [[ "$rc" == "0" || "$rc" == "2" ]] && return 0
    return 1
  else
    # Legacy fallback: word-boundary regex (still false-positives on message
    # bodies that contain the literal bracketed by spaces).
    local pattern="(^|[[:space:]])${flag//./\\.}([[:space:]]|\$)"
    echo "$CMD" | grep -qE "$pattern"
  fi
}

# ── LIVE-/goal guard: a PARKED background watcher disables an armed /goal ─────────────────────────
# CC's Stop handler deletes the /goal Stop hook at any Stop where the task registry holds a
# non-terminal local_bash task, then restores it in a `finally` — the registry always LOOKS healthy
# while the goal is silently skipped (measured on 2.1.220; docs/research/goal-in-handoff-2026-08-08.md
# § RESOLVED). `cc-await-ping` armed via Bash(run_in_background) is exactly such a task, parked for
# hours by design — and CLAUDE.md § Agent Teams instructs that arm, so a goal-armed session
# sabotages its own goal unless the act's own tool call is gated
# (MEMORY.md enforcement-must-live-at-the-chokepoint). A foreground cc-await-ping (cc-wait's use)
# is terminal by the time any Stop happens; an ordinary background build/subagent settles and its
# completion re-invokes the model — both are correct deferrals, untouched. Fail OPEN on any read
# failure: a false deny would strand a goal-less session's only wake path.
#
# ── WIDENED 2026-08-11 FROM ONE TOOL TO THE CLASS (backlog 0e021a9d68e3) ────────────────────────
# THE ASYMMETRY, measured on lead pane 248 the same day. A lead holding a live /goal over a
# five-wave program received 8 HANDOFF-PINGs; every one reached the inbox event-driven and NONE
# entered its context until the operator typed — four `(Checking in)` round-trips over ~2 h. `ps`
# named the cause: a still-alive `Bash(run_in_background)` monitor, pid 46038,
# `until /usr/bin/grep -qE '^→ fired:|ABORT|refus' <file>; do sleep 10; done`. Not cc-await-ping —
# a hand-rolled poller with the identical effect. The guard sat on ONE door (this session was in
# fact REFUSED when it tried to arm cc-await-ping) while the other stood open, and the open one is
# the one an agent reaches for reflexively. (That monitor also could never exit — its predicate
# matched only the success token `^→ fired:` while the fire it watched wrote `!! FIRE FAILED`; a
# watcher whose exit predicate cannot match the failure path parks forever. Separate defect, worth
# knowing, not what this guard fixes.)
#
# DENY, NOT WARN — decided, not defaulted. A non-blocking advisory over every backgrounded command
# under a live goal would fire on 20-second builds where there is no action to take, i.e. an alarm
# that says as little as one that never fires (MEMORY.md alarm-polarity-and-attention-budget). The
# cases this DOES match have a cure, and the deny states it. Delivery also matters: `deny` is the
# one PreToolUse channel measured to reach the model here (this hook's own tests), and an
# `allow`+additionalContext emitted mid-file would additionally SKIP every danger pattern below it.
#
# SHAPE, NOT EXISTENCE — and the reason is that duration is what governs, but duration is not
# knowable at PreToolUse. So the predicate is the structural proxy for UNBOUNDED duration: a
# command whose own termination is not bounded by the work it does. Three members, each a class and
# not a spelling (MEMORY.md denylist-enumerates-spellings-not-the-class):
#   · an event-polling loop — `while`/`until` with a `sleep` in the body: waits on an EXTERNAL
#     event, so nothing it does can end it. This is the measured incident verbatim.
#   · a follow-mode `tail` (-f/-F/--follow): terminates never, by definition.
#   · an explicit park — `sleep N`, N ≥ CC_GOAL_BG_SLEEP_SECS (default 120): the duration is stated
#     in the command itself, which is the one place duration IS readable. `sleep 5` is not the
#     hazard and stays silent.
#   · plus cc-await-ping, the original term, now matched by command position in ANY segment.
# `for` loops are deliberately EXCLUDED: their trip count is bounded by their own list, so they are
# a different (self-terminating) shape. A bg `pnpm build`, a bg test run, a bg subagent — all
# settle and re-invoke the model — stay untouched.
#
# RESIDUAL COVERAGE IS DELIBERATE, because the compensating control already exists at the other
# end: hooks/goal-inert-watch.sh fires at Stop, reads CC's OWN background_tasks payload, and says
# so when an armed goal is actually being skipped. ⚠️ That payload NAMES only BACKGROUNDED parkers
# — CC filters `isBackgrounded === false` out of it while its deferral gate counts any non-terminal
# local_bash, so a FOREGROUND one is invisible there (goal-in-handoff-2026-08-08.md § The
# foreground blind spot, 2026-08-14). The watcher's second arm catches those anyway, from the goal
# going unevaluated across turns; it just cannot name them. Either way the skip is reported, which
# is all this gate's residual coverage rests on: it does not need to be exhaustive — it needs to be
# PRECISE, and to fail open into a Stop-side alarm rather than into silence.
#
# COMMAND-POSITION, not substring: a background `rg 'cc-await-ping' …` is a search that settles in
# seconds, not a parked watcher — substring matching would deny it and teach a falsehood. The
# command is split on its own separators (`;` `|` `&` `&&` `||`, newline) and each segment is
# judged by its FIRST token, so `cd x && cc-await-ping …` is caught while the search is not. (This
# replaces an earlier `*bin/cc-await-ping*` substring term, which existed only to catch the
# compound spelling and would have denied a bg grep for that literal path.)
#
# Rollback knob: CC_GOAL_BG_SLEEP_SECS (park threshold, seconds). Tests:
# tests/validate-bash-goal-guard.bats.
_gg_shape=""
_gg_bg="$_P_BG"   # from the single payload parse at the top — was a second `jq` fork on this path
if [[ "$_gg_bg" == "true" ]]; then
  # (1) whole-command shape — a poll loop's `sleep` lives in a body the segment splitter would
  #     tear apart, so this one is judged over the intact command.
  if [[ "$CMD" =~ (^|[^[:alnum:]_])(while|until)[[:space:]] ]] \
     && [[ "$CMD" =~ (^|[^[:alnum:]_])sleep[[:space:]] ]]; then
    _gg_shape="an event-polling loop (while/until + sleep) — it ends only when something OUTSIDE it happens"
  fi
  # (2) command-POSITION shapes, one judgment per segment.
  if [[ -z "$_gg_shape" ]]; then
    # Pure parameter expansion, no fork: this hook is on the hottest path in the system (every
    # Bash tool call), and the header already records ~18% of the chain lost to exactly this kind
    # of convenience `$( … )`. Two-char operators first, else `&&` would be split by `&`.
    _gg_flat="${CMD//&&/$'\n'}"; _gg_flat="${_gg_flat//||/$'\n'}"
    _gg_flat="${_gg_flat//;/$'\n'}"; _gg_flat="${_gg_flat//|/$'\n'}"
    _gg_flat="${_gg_flat//&/$'\n'}"
    while IFS= read -r _gg_seg; do
      read -r _gg_w1 _gg_a1 _ <<<"$_gg_seg"
      [[ -n "$_gg_w1" ]] || continue
      case "$_gg_w1" in
        *cc-await-ping)
          # ── C6 CARVE-OUT: the chokepoint admits its own cure ──────────────────────────────────
          # docs/research/goal-safe-2way-comms-2026-08-13.md §4. Denying the WHOLE class left a
          # goal-armed session with no idle mode at all: park a watcher and starve the goal, or stay
          # bare and spin it (90 unmet evaluations in 76 min, measured). `--idle-scoped` is the third
          # mode — it stands itself down on any new turn of its own session, so the deferral it
          # creates spans exactly the idle window and the goal is judged once per new-information
          # event. That property is enforced by the tool (it REFUSES to arm when it cannot prove it
          # will self-cancel — bin/cc-await-ping exit 6), which is why a flag is sufficient evidence
          # here: this gate is admitting a shape, not taking the caller's word for a behaviour.
          #
          # PER-SEGMENT, like every other term: the flag has to belong to THIS cc-await-ping, not to
          # some other segment of a compound command. And it is only a carve-out for the
          # command-position term — a `--idle-scoped` arm wrapped in a `while … sleep` loop is still
          # caught by shape (1) above, which runs first and never looks at flags. The loop is the
          # parker there; the self-cancelling watcher inside it cannot help.
          if [[ "$_gg_seg" =~ (^|[[:space:]])--idle-scoped([[:space:]]|$) ]]; then
            continue
          fi
          _gg_shape="a cc-await-ping arm"; break ;;
        sleep|*/sleep)
          if [[ "$_gg_a1" =~ ^[0-9]+$ ]] && (( _gg_a1 >= ${CC_GOAL_BG_SLEEP_SECS:-120} )); then
            _gg_shape="an explicit ${_gg_a1}s park (sleep)"; break
          fi ;;
        tail|*/tail)
          if [[ "$_gg_seg" =~ (^|[[:space:]])(-[a-zA-Z]*[fF][a-zA-Z]*|--follow)([[:space:]=]|$) ]]; then
            _gg_shape="a follow-mode tail — it never terminates on its own"; break
          fi ;;
      esac
    done <<<"$_gg_flat"
  fi
fi
# The goal read is LAST and only here: it greps a transcript that can be multiple MB, and this hook
# fires on EVERY Bash tool call. The shape classifier above is a strictly-narrower necessary
# condition, never a restatement of the goal predicate (MEMORY.md cost-gate-must-be-strictly-weaker),
# so a bg build never pays for it and a goal-less session is never read twice.
if [[ -n "$_gg_shape" ]]; then
  _gg_tp="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)"
  _gg_lib="$LIB_DIR/goal-state.sh"
  [[ -f "$_gg_lib" ]] || _gg_lib="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/goal-state.sh"
  [[ -f "$_gg_lib" ]] || _gg_lib="$HOME/.claude/hooks/lib/goal-state.sh"
  if [[ -f "$_gg_lib" ]]; then
    # shellcheck source=lib/goal-state.sh
    # shellcheck disable=SC1091  # runtime-resolved fallback chain
    source "$_gg_lib" 2>/dev/null || true
  fi
  if command -v goal_live_condition >/dev/null 2>&1; then
    _gg_cond="$(goal_live_condition "$_gg_tp" 2>/dev/null)" || _gg_cond=""
    if [[ -n "$_gg_cond" ]]; then
      # THE DENY TEACHES THE ADMITTED FORM (C7). Until 2026-08-16 this text said only "do not park a
      # background watcher here", which is correct about the shape in hand and silent about the
      # state the model is actually in: a session with nothing to do and a goal whose truth lives in
      # someone else's progress. That silence is what produced the spin pole — the model complies,
      # stays bare, and re-judges an unchanged world every ~51 seconds. So the refusal now names the
      # one shape that IS safe, and it names it with this session's own id, because the flag without
      # a resolvable beat oracle is a refusal at the tool (exit 6) rather than a wake path.
      _gg_sid="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)"
      # $HOME, never "~/…" — the model pastes this verbatim and a tilde inside a quoted string is not
      # a path (SC2088; same rule hooks/session-continue.sh:476 states for its own arm command).
      if [[ -n "$_gg_sid" ]]; then
        _gg_arm="$HOME/.claude/bin/cc-await-ping --idle-scoped --sid ${_gg_sid}"
      else
        _gg_arm="$HOME/.claude/bin/cc-await-ping --idle-scoped --sid <this session's id>"
      fi
      deny "A /goal is LIVE in this session (\"${_gg_cond:0:120}\"), and this backgrounded command is ${_gg_shape}, which would silently disable it: Claude Code skips /goal evaluation at every Stop while a non-terminal background Bash exists (the registry is restored afterwards, so nothing ever looks wrong). Do not park a background watcher here. You are not deaf without it — the goal blocks your stops, so you keep taking turns and mailbox-drain delivers peer mail at every turn boundary; the birth watcher (mailbox-wake-arm, asyncRewake) also wakes a genuinely idle session WITHOUT entering the task registry. If you have nothing actionable and are waiting on an EXTERNAL event (a fired peer, an operator answer), the one arm that is safe under a live goal is the idle-scoped awaiter — it stands itself down on your next turn, so the deferral lasts exactly as long as the idle does: ${_gg_arm} (run it as your LAST action, backgrounded, on a clean committed state; it refuses to arm — exit 6 — if mail is already pending, a sibling watcher is live, or it cannot read your turn beat). If instead you need a cross-turn continuation lever, use: ~/.claude/hooks/session-continue.sh set \"<next step>\" — it is goal-safe. Detail: docs/research/goal-safe-2way-comms-2026-08-13.md §4 · docs/research/goal-in-handoff-2026-08-08.md"
    fi
  fi
fi

# ── DUPLICATE-WORKER PANE-SPAWN ADMISSION ────────────────────────────────────────────────────────
# The THIRD consumer of the duplicate-worker lease (backlog f2617b0480df). The other two are
# hooks/check-edit-boundary.sh (PreToolUse|Write|Edit — stops a duplicate CORRUPTING the worktree)
# and hooks/agent-teams-enforce.sh (PreToolUse|Agent — stops it SPENDING the fleet on subagents).
#
# ⚠️ THIS TERM DID NOT BOUND THE 2026-08-07 CASCADE, AND THIS BLOCK USED TO SAY IT DID (corrected
# 2026-08-11, backlog 6f24f9c49e3e). The claim it carried — "the first one on the surface where the
# measured runaway actually happened" — is false: that cascade never touched Bash. See § WHICH
# SURFACE THE CASCADE ACTUALLY CROSSED below for the measurement and for this term's real (non-empty,
# smaller) population. The term stays; only the attribution was wrong.
#
# WHY A THIRD POINT AT ALL — because neither of the first two can see the cascade they were built
# for. Measured 2026-08-11 against the full IDL history (985k rows, 2026-08-08 → 2026-08-11):
#
#   surface                        cap                          evaluations   sees the cascade?
#   Agent tool, in-process depth   CC_SPAWN_MAX_DEPTH=2         43            NO — empty population
#   Agent tool, per-session count  CC_SPAWN_MAX_PER_SESSION=60  43            NO — counter resets
#   Write/Edit, lease identity     worker-claim-gate            793           after the fact
#   Agent tool, lease identity     worker-claim-gate            6             YES — THE ACTUAL BOUND
#   Bash → pane spawn              (none)                       —             ungated → this term
#
# The last two rows are CORRECTED (2026-08-11, backlog 6f24f9c49e3e). This table shipped with
# "Bash → pane spawn / THIS IS THE ACTUATOR" and no Agent-lease row at all, and it had the two
# backwards — see below.
#
# The depth term's population is EMPTY BY HARNESS CONSTRUCTION, which resolves the open unknown
# recorded at hooks/agent-teams-enforce.sh — see the note landed there in the same commit. All 43
# of its evaluations read `basis=depth-toplevel`, depth 0, and always will: Claude Code does not
# expose the Agent tool to subagents at all, so an in-process spawn cannot nest and `spawnDepth`
# can never exceed the value the lead already has. The per-session budget is real but resets at
# exactly the edge the cascade traverses — every step of the 2026-08-07 blow-up MINTED A NEW CLI
# SESSION, so 91+ sessions each sat perfectly inside a cap of 60 (memory
# `counter-resets-at-the-boundary-the-runaway-crosses`).
#
# ── WHICH SURFACE THE CASCADE ACTUALLY CROSSED (corrected 2026-08-11, backlog 6f24f9c49e3e) ──────
# THE SUPERSEDED CLAIM, kept because the inference is the instructive part: "the sessions were
# minted HERE — `logs/pane-spawns.jsonl` records 324 spawns carrying a bare `chain:"it2-kitty"`
# where a real fire stamps `chain:"handoff-fire.sh>it2-kitty"`, i.e. a pane split executed as an
# ordinary Bash command ... not the dispatcher, not the Agent tool, but `Bash`."
#
# The premise is true and the conclusion does not follow. A bare chain means only that
# handoff-fire.sh was NOT in the call path. It does not name what WAS, and "Bash" was assumed, never
# read. What actually spawns those panes is Claude Code's own teammate-pane backend: an `Agent` call
# carrying a `name`/`team_name` invokes `it2-kitty` DIRECTLY (memory `vendor-gate-may-be-an-env-var`
# — that backend gates on ITERM_SESSION_ID + `command -v it2`, no handshake), so no handoff-fire.sh
# appears in the chain and no Bash tool call exists to gate.
#
# Five legs, all from the 2026-08-07T22:00–23:30Z window, the cascade itself:
#   1. VOLUME MATCHES THE AGENT TOOL, NOT BASH — 187 Agent/Task calls carrying a name/team_name vs
#      180 bare-chain `it2-kitty` spawns, tracking ~1:1 minute by minute across the whole window.
#   2. THERE ARE NO BASH SPAWNS TO COUNT — all 167 cascade transcripts hold 34 Bash calls naming a
#      pane tool, and every one is `self-close`, a `sed`/`grep` READ of handoff-fire.sh, or
#      `cc-backlog needs`. Not one invokes `it2-kitty`, `kitty-split-launch.sh` or `cc-respawn`.
#   3. THE PROCESS TREE EXCLUDES A TOOL SHELL — those rows record ancestry `it2-kitty ← claude`
#      (ppid_comm=claude, 179/180). A Bash tool call cannot produce that: it runs the command under
#      the tool's own shell, which necessarily sits between.
#   4. THE SAME LOG CARRIES ITS OWN POSITIVE CONTROL — `chain:"kitty-split-launch.sh"` rows, which
#      ARE session-invoked, show exactly the shape leg 3 says is missing: `←zsh←claude`, 16/16. So
#      the discriminator is a property of the log, not of how this analysis chose to read it.
#   5. `detail` records `argv:0` — the backend splits with no arguments; a session driving a pane
#      tool from Bash passes some.
#
# WHERE THE GENERATION BOUND ACTUALLY LIVES: hooks/agent-teams-enforce.sh, whose `cc_worker_claim_admit
# agent-tool` term (834fa840) sits on PreToolUse|Agent — the surface legs 1-5 identify. The lease
# HOLDER's fan-out is admitted, so gen 0 → gen 1 proceeds normally; every session it puts in that
# worktree is a duplicate, so ITS Agent calls are refused and the recursion terminates at
# generation 2. That is end-to-end red-proofed by case 13 of tests/worker-claim-gate-coverage.bats
# ("the Agent hook actually DENIES a spawn from a session that lacks the lease"), with a control so
# the deny cannot be an unconditional refusal of every Agent call in a wt- dir. 🚨 DO NOT DELETE
# THAT TERM AS REDUNDANT WITH THIS ONE — this one would not have seen the cascade at all.
#
# WHAT THIS TERM IS STILL FOR, measured rather than assumed (the whole defect above was an unmeasured
# population): a session running a pane tool from Bash is a real, non-empty, and much smaller class —
# all-time 91 rows have `claude` in their ancestry under a session-invoked chain (72 handoff-fire.sh*,
# 16 kitty-split-launch.sh, 3 lr-handoff.sh), against 368 handoff-fire.sh* rows fired headless by
# launchd/cron and 296 lr-reset-poller.sh. Every `self-close` among them is exempt by construction
# below. So this term closes a genuine hole on a surface nothing else gates — it is simply not the
# hole the 2026-08-07 blow-up went through.
#
# RE-DERIVE, DO NOT TRUST, THESE FIGURES (memory `published-figure-decays-with-its-source`; the
# transcript corpus is the perishable half):
#   jq -r 'select(.chain=="it2-kitty")|.ancestry' ~/.claude/logs/pane-spawns.jsonl | head
#   ls ~/.claude-quaternary/projects/*wt-149789b69fc4/*.jsonl | wc -l
#
# WHY IN THIS HOOK — it is ALREADY registered on PreToolUse|Bash, so the term goes live on the
# trunk fast-forward instead of waiting behind a settings.json C10 operator step in the activation
# queue, where gates rot >24h. Same reasoning that placed the capacity and depth terms inside
# agent-teams-enforce.sh rather than a new hook file (the inertness generator).
#
# THE PRE-FILTER IS A COST GATE, NOT THE PREDICATE. This hook fires on EVERY Bash call on the box,
# and the library's real check forks. So a forkless command-position match selects the candidates
# and the LEASE decides — identity, which spans the cascade, never a spelling. That ordering is
# what keeps this from being a denylist over ways to say "spawn a pane" (memory
# `denylist-enumerates-spellings-not-the-class`): a spelling this filter misses simply falls
# through to today's behaviour, which is ungated, so a miss can never be a REGRESSION — only a
# smaller improvement. The class is closed on the other side, by the lease.
#
# THE GATE ALLOWS ITS OWN CURE. `self-close` is the exact command the refusal instructs a duplicate
# to run, so it is exempt unconditionally — a guard that forbids its own prescribed remedy re-emits
# forever (memory `work-item-remedy-can-become-forbidden`).
#
# FAIL OPEN, NEVER SILENTLY: library unreachable ⇒ admit AND record, so "was this surface gated?"
# is answerable from the same store as the verdicts (memory
# `sensor-default-off-makes-blindness-the-shipping-path` — one value must never mean both
# "answered no" and "could not ask").
_wcs_first="${CMD%%[[:space:]]*}"
_wcs_hit=0
case "$_wcs_first" in
  *it2-kitty|*kitty-split-launch.sh|*kitty-pane-menu|*handoff-fire.sh|*cc-respawn|*lr-handoff.sh|*lr-fire-resume.sh|*lr-reset-poller.sh) _wcs_hit=1 ;;
esac
case "$CMD" in
  *bin/it2-kitty*|*bin/kitty-split-launch.sh*|*bin/kitty-pane-menu*|*bin/cc-respawn*|*scripts/handoff-fire.sh*|*limit-recover/lr-handoff.sh*|*limit-recover/lr-fire-resume.sh*|*limit-recover/lr-reset-poller.sh*) _wcs_hit=1 ;;
esac
# The cure, and the same-pane relaunch that mints no session, are never refused.
case "$CMD" in *self-close*) _wcs_hit=0 ;; esac
if [[ "$_wcs_hit" == 1 && "${CC_WCLAIM_GATE:-on}" != off ]]; then
  _wcs_self="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
  for _wcs_lib in "$(dirname "$_wcs_self")/../scripts/lib/worker-claim-gate.sh" \
                  "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/lib/worker-claim-gate.sh" \
                  "${HOME:-}/.claude/scripts/lib/worker-claim-gate.sh"; do
    # shellcheck disable=SC1090  # runtime-resolved source; the ship gate runs shellcheck without -x
    [[ -f "$_wcs_lib" ]] && . "$_wcs_lib" 2>/dev/null && break
  done
  if command -v cc_worker_claim_admit >/dev/null 2>&1; then
    _wcs_cwd="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
    [[ -n "$_wcs_cwd" ]] || _wcs_cwd="$PWD"
    if ! CC_WCLAIM_SID="$(printf '%s' "$INPUT" | jq -r '.session_id // "?"' 2>/dev/null || echo '?')" \
         cc_worker_claim_admit pane-spawn "$_wcs_cwd" "pane spawn"; then
      deny "DUPLICATE WORKER — pane spawn refused. This session does not hold the lease on item $(cc_worker_claim_item). $(cc_worker_claim_reason). Another LIVE session ($(cc_worker_claim_holder)) is doing this work right now, and spawning a pane from a duplicate is how one dispatch became 224 spawns / 167 sessions across 3 generations in ~38 minutes: every step minted a fresh CLI session, which reset both spawn counters to zero, so 91 sessions each read perfectly healthy inside a cap of 60. DO NOT retry and DO NOT re-word the command — the refusal is a FACT about a live lease, read from your working directory, not from your text. STAND DOWN: stop work. Retiring this pane is CONDITIONAL on how it was started, not a step you can assume: \`\$HOME/.claude/scripts/handoff-fire.sh self-close --terminal\` is exempt from THIS gate by construction and refuses a dirty tree (the intended safety), but it closes this pane only if the pane was FIRED as a peer. With no fired-peer stamp — every operator-launched pane and every Agent-Team lead — self-close exits 2, ORIGIN session, not a fired peer, and such a session STAYS UP and reports instead of closing. Standing down is the instruction either way. If you believe the incumbent is DEAD, do not force it — the lease self-releases the moment its claimer dies or \`cc-backlog reap\` ages the claim out, and the next spawn is admitted automatically. Override for this session only: CC_WCLAIM_GATE=off. Rule: backlog f2617b0480df, docs/plans/CONCURRENCY_PROGRAM.md#s4."
    fi
  else
    jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')" \
      '{ts:$ts,hook:"worker-claim-gate",sid:"?",disposition:"abstained",reason:"duplicate-worker",
        gate:"worker-claim-gate",verdict:"admit",basis:"absent",caller:"pane-spawn",
        what:"pane spawn",detail:"scripts/lib/worker-claim-gate.sh unreachable — pane spawn UNGATED for duplicate workers"}' \
      >> "${CC_WCLAIM_IDL:-$HOME/.claude/autonomy/idl.jsonl}" 2>/dev/null || true
  fi
fi

# ── SPAWN-LINEAGE GENERATION CAP ─────────────────────────────────────────────────────────────────
# The SECOND term on this surface (backlog bffbce207f12), and it exists for the population the term
# above cannot see. `cc_worker_claim_admit` keys on the cwd being `wt-<12 lowercase hex>` and
# abstains on anything else — correct for a lease, since without a worktree there is no item and no
# claim. But that abstention is most of the fleet, and the fan-outs beyond it are the widest ones.
# Measured 2026-08-11 over all 1085 rows of logs/pane-spawns.jsonl:
#
#   cwd class                            spawns   distinct claude spawners   max fan-out by one
#   dispatch wt-<12hex>  (lease binds)      214             40                      7
#   shared repo root     (lease abstains)   303             23                     21   ← 5 sessions ≥10
#
# So the bound that exists works and the uncovered population is the one carrying the worst shapes.
# Identity is still the instrument — a per-session COUNT resets at exactly the edge a cascade
# crosses (memory `counter-resets-at-the-boundary-the-runaway-crosses`) — but where the ledger has
# no identity to offer, one has to be carried. scripts/lib/spawn-lineage.sh carries it, and its
# header records the probe that proves it can: the OS process tree is severed at the kitty daemon,
# so an explicit `--env` stamp from bin/it2-kitty is the only thing that crosses a pane boundary.
#
# ONLY THE GENERATION IS ENFORCED. Width per root is counted by the library and never refused: the
# widest legitimate observation (21) and the pathological one are not separated by any threshold
# this data supports, and a bound sitting inside the survived band can only manufacture false
# refusals (memory `threshold-must-separate-fatal-from-survived`). The counter ships so a later
# reader has the distribution; it does not gate.
#
# SAME PRE-FILTER, DELIBERATELY. `_wcs_hit` above already selects the pane-spawn commands and
# already zeroes itself on `self-close`, so this term inherits both the population and the
# gate-allows-its-own-cure exemption rather than re-deriving either (memory
# `work-item-remedy-can-become-forbidden`, `denylist-enumerates-spellings-not-the-class`).
#
# FAIL OPEN, LOUDLY. Library unreachable, stamp absent, or stamp unparseable ⇒ ADMIT plus one IDL
# row with a distinct `basis`, so "unstamped" never reads the same as "could not ask".
if [[ "$_wcs_hit" == 1 && "${CC_LINEAGE_GATE:-on}" != off ]]; then
  _lin_self="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
  for _lin_lib in "$(dirname "$_lin_self")/../scripts/lib/spawn-lineage.sh" \
                  "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/lib/spawn-lineage.sh" \
                  "${HOME:-}/.claude/scripts/lib/spawn-lineage.sh"; do
    # shellcheck disable=SC1090  # runtime-resolved source; the ship gate runs shellcheck without -x
    [[ -f "$_lin_lib" ]] && . "$_lin_lib" 2>/dev/null && break
  done
  if command -v cc_lineage_admit >/dev/null 2>&1; then
    if ! cc_lineage_admit pane-spawn \
           "$(printf '%s' "$INPUT" | jq -r '.session_id // "?"' 2>/dev/null || echo '?')" \
           "pane spawn"; then
      deny "SPAWN GENERATION CAP — pane spawn refused. This session is generation $(cc_lineage_gen) of spawn lineage $(cc_lineage_root), and the cap is ${CC_LINEAGE_MAX_GEN:-3}: $(cc_lineage_reason). Generation is read from an environment stamp this machine wrote when your pane was created, NOT from your text — so do not retry and do not re-word the command, it will read exactly the same. The ladder the cap protects is desk → wave lead → dispatched phase session → that session's own teammates; you are one rung past it, and past it is where a fan-out stops being a wave and becomes the recursion that reached 224 spawns / 167 sessions in ~38 minutes and ignited the kernel watchdog panics that destroy every live session at once. INSTEAD: do this work SERIALLY in this session, or RETURN your findings to the session that spawned you and let it decide whether to widen — it has generations you do not. Retiring this pane (\`\$HOME/.claude/scripts/handoff-fire.sh self-close --terminal\`) is exempt from THIS gate by construction — but self-close has an origin gate of its own, so closing is CONDITIONAL: with no fired-peer stamp it exits 2, ORIGIN session, not a fired peer, and the pane STAYS UP. Returning your findings is the step that always works. Override for this session only: CC_LINEAGE_GATE=off, or raise the ladder with CC_LINEAGE_MAX_GEN=<n>. Rule: backlog bffbce207f12, docs/research/spawn-lineage-probe-2026-08-11.md."
    fi
  else
    jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')" \
      '{ts:$ts,hook:"spawn-lineage",sid:"?",disposition:"abstained",reason:"spawn-lineage",
        gate:"spawn-lineage",verdict:"admit",basis:"absent",caller:"pane-spawn",
        what:"pane spawn",detail:"scripts/lib/spawn-lineage.sh unreachable — pane spawn UNGATED for lineage"}' \
      >> "${CC_LINEAGE_IDL:-${CC_ADMIT_IDL:-$HOME/.claude/autonomy/idl.jsonl}}" 2>/dev/null || true
  fi
fi

# ── DUPLICATE-WORKER BASH-WRITE ADMISSION ────────────────────────────────────────────────────────
# The FOURTH consumer of the duplicate-worker lease (backlog f5c3cfb86e2e), and the one that covers
# the write path this fleet actually uses. The other three: hooks/check-edit-boundary.sh
# (PreToolUse|Write|Edit|MultiEdit), hooks/agent-teams-enforce.sh (PreToolUse|Agent), and the
# pane-spawn term directly above.
#
# ── WHY A FOURTH, WHEN "the write" WAS ALREADY GATED ───────────────────────────────────────────
# Because the gate on Write/Edit and the writes this fleet performs are two different populations.
# Auto mode's standing session instruction is:
#
#   "make file changes with sed, heredocs, or short scripts, rather than using the dedicated Read,
#    Edit, or Write tools"
#
# So in the mode this box runs, the ROUTINE edit never reaches the Write|Edit matcher at all — it
# arrives here, as Bash. check-edit-boundary.sh is not wrong and is not redundant; it simply sits
# on a surface the common case no longer crosses. This is the same shape the pane-spawn term above
# records for the 2026-08-07 cascade (a bound whose population is empty by construction), arriving
# one surface later, and the same shape as the per-session spawn counter that reset at exactly the
# edge the runaway traversed.
#
# MEASURED, NOT INFERRED. Pane 71 (MacBookPro-88086) appended two blocks to
# hooks/lib/mailbox-pending.sh in wt-0366d5cc7b87 through a `python3 - <<'PY'` heredoc under Bash
# with NO refusal, while the lease HOLDER pane 70 (MacBookPro-67081) was mid-edit on that same
# file — producing a duplicate `mailbox_peek_from` definition that shadowed the holder's (in bash
# the later definition wins), i.e. precisely the silent divergence the lease exists to prevent. The
# predicate was healthy the whole time and said so: run by hand in that same shell,
# `cc_worker_claim_admit` returned REFUSED, "0366d5cc7b87 is held by MacBookPro-67081; this session
# is MacBookPro-88086". The decision was correct and unreachable — coverage, not logic, which is
# the founding defect of this whole gate (scripts/lib/worker-claim-gate.sh § THE DEFECT).
#
# RE-DERIVED HERE BEFORE THIS TERM WAS WRITTEN, with a positive control on the same fixture: the
# item's exact heredoc payload, in a wt- dir whose ledger refuses, ran through this hook and
# produced EMPTY output at rc 0 — admitted — while a pane-spawn payload against the SAME refusing
# ledger in the SAME worktree denied. So the hole was in the occasion, never in the instrument.
#
# ── THE DOWNSTREAM THIS RESTORES ───────────────────────────────────────────────────────────────
# backlog b03eb3f28845 was closed REFUTED on the finding that "a PreToolUse deny IS the turn
# boundary a message lacks" — the reason this repo needs no separate stand-down actuator for the
# refused worker. That refutation is sound exactly where the deny FIRES. In auto mode on a
# Bash-driven edit it did not fire, so the stand-down channel was silent on the commonest write
# path, and the refutation was resting on a surface the traffic had left. This term puts the
# traffic back under the deny.
#
# ── THE PRE-FILTER IS A COST GATE, NOT THE PREDICATE (the same rule as the term above) ─────────
# This hook fires on EVERY Bash call on the box and the library's real check forks, so a forkless
# shape match selects candidates and the LEASE decides — identity, never a spelling. A write
# spelling this filter misses falls through to today's behaviour, which is ungated, so a miss is
# never a REGRESSION, only a smaller improvement (memory `denylist-enumerates-spellings-not-the-
# class`). Over-matching is safe in the other direction too, and this is the load-bearing asymmetry:
# `cc_worker_claim_admit` ADMITS whenever the cwd is not a `wt-<12hex>` dispatch worktree or the
# session holds the lease, so a false shape match can only ever reach a session that is ALREADY
# required to stand down. It cannot reach the holder.
#
# READS STAY ADMITTED, AND THAT IS DELIBERATE. Case 15's CONTROL 3 pins the same commitment for the
# spawn term — "a duplicate must keep the Bash it needs to inspect, checkpoint and retire". So the
# redirect arm strips `2>&1`, `>&2` and every `/dev/null` target BEFORE asking whether a `>` remains;
# without that strip, `grep … 2>/dev/null` is a write and the gate degenerates into a refusal of the
# whole Bash surface, which carries as few bits as one that never fires (memory
# `alarm-polarity-and-attention-budget`).
#
# THE GATE ALLOWS ITS OWN CURE. `self-close` is exempt unconditionally, for the reason the term
# above states: a guard that forbids its own prescribed remedy re-emits forever (memory
# `work-item-remedy-can-become-forbidden`). The stand-down REPORTING path — cc-backlog, cc-notify,
# cc-custody — matches no arm below, by construction: no redirect, no heredoc, no write verb in
# command position.
#
# FAIL OPEN, NEVER SILENTLY: library unreachable ⇒ admit AND record, so "was this surface gated?"
# is answerable from the same store as the verdicts.
_wbw_hit=0
if [[ "${CC_WCLAIM_GATE:-on}" != off ]]; then
  # ARM 1 — a redirection whose target is a FILE. Strip fd duplication and /dev/null first; what
  # survives is a write. Pure parameter expansion, bash 3.2-safe, zero forks.
  _wbw_scan="$CMD"
  _wbw_scan="${_wbw_scan//2>&1/ }"; _wbw_scan="${_wbw_scan//1>&2/ }"
  _wbw_scan="${_wbw_scan//>&2/ }";  _wbw_scan="${_wbw_scan//>&1/ }"
  _wbw_scan="${_wbw_scan//&>>\/dev\/null/ }"; _wbw_scan="${_wbw_scan//&>\/dev\/null/ }"
  _wbw_scan="${_wbw_scan//2>> \/dev\/null/ }"; _wbw_scan="${_wbw_scan//2>>\/dev\/null/ }"
  _wbw_scan="${_wbw_scan//2> \/dev\/null/ }";  _wbw_scan="${_wbw_scan//2>\/dev\/null/ }"
  _wbw_scan="${_wbw_scan//>> \/dev\/null/ }";  _wbw_scan="${_wbw_scan//>>\/dev\/null/ }"
  _wbw_scan="${_wbw_scan//> \/dev\/null/ }";   _wbw_scan="${_wbw_scan//>\/dev\/null/ }"
  case "$_wbw_scan" in *'>'*) _wbw_hit=1 ;; esac

  # ARM 2 — a heredoc fed to something that can write. This is the shape the incident used
  # (`python3 - <<'PY'` … `open(…,'a').write(…)`), and no redirect appears in it anywhere.
  # `*sh` deliberately subsumes bash/zsh/sh and any `./foo.sh`, and `*ed` subsumes sed/ed — spelling
  # them out separately is what shellcheck flags as SC2221/SC2222, and the subsuming pattern is the
  # wider one anyway, which is the safe direction for a cost filter.
  if [[ "$_wbw_hit" == 0 ]]; then
    case "$CMD" in
      *'<<'*)
        case "${CMD%%[[:space:]]*}" in
          *python3|*python|*perl|*ruby|*node|*sh|*awk|*ed|*cat|*tee|*patch|*dd)
            _wbw_hit=1 ;;
        esac ;;
    esac
  fi

  # ARM 3 — a write verb. Command position first, then a whole-command pass for the path-qualified
  # and post-separator spellings the first pass cannot see (`cd x && rm y`, `cat a | tee b`).
  if [[ "$_wbw_hit" == 0 ]]; then
    case "${CMD%%[[:space:]]*}" in
      *cp|*mv|*rm|*mkdir|*rmdir|*touch|*tee|*ln|*install|*patch|*truncate|*dd|*chmod|*chown|*ed)
        _wbw_hit=1 ;;
    esac
  fi
  if [[ "$_wbw_hit" == 0 ]]; then
    case "$CMD" in
      *'sed -i'*|*'perl -i'*|*'ruby -i'*|*'| tee'*|*'|tee'*|*'tee -a'*|*'&& rm '*|*'; rm '*|\
      *'&& mv '*|*'; mv '*|*'&& cp '*|*'; cp '*|*'&& mkdir'*|*'; mkdir'*|*'&& touch'*|*'; touch'*|\
      *'git apply'*|*'git commit'*|*'git add '*|*'git checkout'*|*'git restore'*|*'git rm '*|\
      *'git mv '*|*'git reset'*|*'git stash'*|*'git push'*|*'git merge'*|*'git rebase'*|\
      *'shfmt -w'*|*'prettier --write'*|*'ruff format'*|*'dd of='*|*'install -m'*|*'patch -p'*)
        _wbw_hit=1 ;;
    esac
  fi

  # The cure is never refused — the same exemption, and the same reason, as the term above.
  case "$CMD" in *self-close*) _wbw_hit=0 ;; esac
fi
# FORKLESS PRE-SCREEN ON THE PAYLOAD, and it is why this term is affordable on this hook. A write
# is COMMON — unlike a pane spawn, which is rare — so resolving the library and forking `jq` for the
# cwd on every write would add two execs to the hottest path in the fleet, which is the cost
# docs/plans/HOOK_CHAIN_COST.md exists to stop (this hook already paid 11.6 ms of a 71.9 ms modal
# path to three duplicate `jq` reads of one payload, backlog 054499f0c342). The lease can only bind
# in a `wt-<12hex>` dispatch worktree, and such a cwd necessarily contains the substring `/wt-`
# SOMEWHERE in the payload — so a pure parameter match on $INPUT skips the whole term, at zero
# forks, for every session that is not in one. It cannot produce a miss: the substring is implied by
# the shape the library keys on. A false HIT (the text appears in the command rather than the cwd)
# costs one jq and is then decided correctly by the library, which abstains on a non-worktree cwd.
case "$INPUT" in *'/wt-'*) ;; *) _wbw_hit=0 ;; esac
if [[ "$_wbw_hit" == 1 ]]; then
  _wbw_self="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
  for _wbw_lib in "$(dirname "$_wbw_self")/../scripts/lib/worker-claim-gate.sh" \
                  "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/lib/worker-claim-gate.sh" \
                  "${HOME:-}/.claude/scripts/lib/worker-claim-gate.sh"; do
    # shellcheck disable=SC1090  # runtime-resolved source; the ship gate runs shellcheck without -x
    [[ -f "$_wbw_lib" ]] && . "$_wbw_lib" 2>/dev/null && break
  done
  if command -v cc_worker_claim_admit >/dev/null 2>&1; then
    _wbw_cwd="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
    [[ -n "$_wbw_cwd" ]] || _wbw_cwd="$PWD"
    if ! CC_WCLAIM_SID="$(printf '%s' "$INPUT" | jq -r '.session_id // "?"' 2>/dev/null || echo '?')" \
         cc_worker_claim_admit bash-write "$_wbw_cwd" "file write via Bash"; then
      deny "DUPLICATE WORKER — file write refused. This session does not hold the lease on item $(cc_worker_claim_item). $(cc_worker_claim_reason). Another LIVE session ($(cc_worker_claim_holder)) holds it and is editing this worktree right now. Routing the edit through Bash does not change that: a \`sed -i\`, a redirect and a \`python3 - <<'PY'\` heredoc are the same act as the Write tool, and this is the exact path that put a DUPLICATE \`mailbox_peek_from\` into hooks/lib/mailbox-pending.sh on 2026-09-10 — a later definition silently shadowing the holder's, with no error anywhere. DO NOT retry, DO NOT re-word the command, and DO NOT work around this by writing elsewhere — you are the duplicate, and the refusal is a FACT about a live lease read from your working directory, not a transient throttle and not a judgement about your text. STAND DOWN: stop work. Retiring this pane is CONDITIONAL on how it was started, not a step you can assume: \`\$HOME/.claude/scripts/handoff-fire.sh self-close --terminal\` is exempt from THIS gate by construction and refuses a dirty tree (the intended safety), but it closes this pane only if the pane was FIRED as a peer. With no fired-peer stamp — every operator-launched pane and every Agent-Team lead — self-close exits 2, ORIGIN session, not a fired peer, and such a session STAYS UP and reports instead of closing. Standing down is the instruction either way. Reporting is NOT refused: cc-backlog, cc-notify and cc-custody match no arm of this gate. If you believe the incumbent is DEAD, do not force it — the lease self-releases the moment its claimer dies or \`cc-backlog reap\` ages the claim out, and the next write is admitted automatically. Override for this session only: CC_WCLAIM_GATE=off. Rule: backlog f5c3cfb86e2e, docs/plans/CONCURRENCY_PROGRAM.md#s4."
    fi
  else
    jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')" \
      '{ts:$ts,hook:"worker-claim-gate",sid:"?",disposition:"abstained",reason:"duplicate-worker",
        gate:"worker-claim-gate",verdict:"admit",basis:"absent",caller:"bash-write",
        what:"file write via Bash",detail:"scripts/lib/worker-claim-gate.sh unreachable — Bash-driven file writes UNGATED for duplicate workers"}' \
      >> "${CC_WCLAIM_IDL:-$HOME/.claude/autonomy/idl.jsonl}" 2>/dev/null || true
  fi
fi

# ── Hard deny: catastrophic or rule-violating patterns ────────────────

# System damage, part 1 — the two shapes that are NOT an rm argv question. A fork bomb is syntax,
# not a command with flags; `sudo rm` is a two-token shape whose breadth (any rm at all under
# sudo) is deliberate. Both keep their text matching, unchanged.
if echo "$CMD" | grep -qE '(sudo[[:space:]]+rm|:\(\)\{[[:space:]]*:\|:&[[:space:]]*\};:)'; then
  deny "Dangerous command pattern blocked: potential system damage (sudo rm, or fork bomb)."
fi

# ── System damage, part 2 — catastrophic rm, decided on ARGV ──────────
# The regex this replaces hardcoded ONE spelling of the flags, `-rf`, so every equivalent spelling
# walked past it. Measured against the shipped hook (codex-security scan dc12c8db, finding 1):
#     rm -rf /*                 deny          ← the only spelling it knew
#     rm -fr /*                 ask           ← downgraded
#     rm -r -f /*               ask           ← downgraded
#     rm -Rf /                  NO DECISION   ← -R is the same flag
#     rm -f -r /                NO DECISION
#     rm --recursive --force /* NO DECISION   ← the long form is not a flag bundle at all
#     rm -rf /                  ask           ← the slash branch ended in `[^a-zA-Z]`, which must
#                                               CONSUME a character, so bare `/` at end-of-input
#                                               could not match — while the tilde branch beside it
#                                               was written `~(/|$|…)` and did accept it. That
#                                               internal disagreement is what proves oversight
#                                               rather than intent.
# The equivalence class is not enumerable by regex — flag order, bundling, case, long form and
# `--` separation multiply — so the spelling question is answered by tokenizing instead:
# rm_argv_scan reports (recursive, force, target) per real invocation, and the rule reads exactly
# as it is written in CLAUDE.md. That also fixes the mirror-image defect, since text is not
# execution: `git commit -m "fix: guard rm -rf / properly"` used to be DENIED, so the guard
# blocked its own fix from being committed.
#
# ONE scan, TWO consumers (this deny and the non-build-target warn below): a second parse would be
# a second place for the spelling rule to rot out of sync.
RM_SCAN=""
RM_SCAN_OK=0
RM_PRESENT=0
if printf '%s' "$CMD" | grep -qE '(^|[^a-zA-Z0-9_-])rm([[:space:]]|$)'; then
  RM_PRESENT=1
  # `declare -F` is not ceremony: hooks/ deploys as per-file symlinks, so a live layer can briefly
  # hold a NEW validate-bash.sh beside an OLD lib. Absent function → legacy path, never a crash.
  if [[ "$HAVE_IS_TRUE_FLAG" == "1" ]] && declare -F rm_argv_scan >/dev/null 2>&1; then
    if RM_SCAN=$(rm_argv_scan "$CMD"); then
      RM_SCAN_OK=1
    fi
  fi
fi

# is_catastrophic_rm_target <argv-token> — the TARGET half of the predicate. Deliberately the same
# REACH as the regex it replaces, so this change moves only the flag and quoting spellings and
# never which targets count:
#   /  //  /*  /.        root itself or a root-level glob — but NOT /usr, /etc, which stay `ask`
#   ~  ~/  ~/anything    the tilde branch's existing prefix reach
#   $HOME…  ${HOME}…     the $HOME branch's existing prefix reach; ${HOME} is the same variable,
#                        spelled differently, which is the very defect class being fixed here
is_catastrophic_rm_target() {
  local t="$1"
  local re_root='^/([^a-zA-Z].*)?$'
  local re_tilde='^~(/.*)?$'
  local re_home='^\$\{?HOME\}?'
  [[ "$t" =~ $re_root || "$t" =~ $re_tilde || "$t" =~ $re_home ]]
}

deny_catastrophic_rm() {  # <target> — one message, so both paths below cannot drift apart
  deny "Dangerous command pattern blocked: potential system damage — recursive+force rm targeting '$1' (root or home). Flag spelling is irrelevant: -rf, -fr, -Rf, -r -f, --recursive --force and every bundle containing r/R and f are the same command. If you meant a path INSIDE the tree, name it relatively."
}

if [[ "$RM_PRESENT" == "1" && "$RM_SCAN_OK" == "1" ]]; then
  while IFS=$'\t' read -r rm_rec rm_force rm_target; do
    [[ "$rm_rec" == "1" && "$rm_force" == "1" ]] || continue
    is_catastrophic_rm_target "$rm_target" && deny_catastrophic_rm "$rm_target"
  done <<<"$RM_SCAN"
elif [[ "$RM_PRESENT" == "1" ]]; then
  # UNCLEAR (python3 absent / unbalanced quotes) or VALIDATE_BASH_LEGACY=1. No argv, so decide on
  # text — over-blocking a message body exactly as this clause always did. Still spelling-aware,
  # so the rollback knob is a rollback of the PARSER, never a re-opening of the bypass.
  RM_TEXT_OCC=$(printf '%s' "$CMD" | grep -oE '(^|[^a-zA-Z0-9_-])rm([[:space:]]+[^;&|]*)?' || true)
  while IFS= read -r rm_occ; do
    [[ -z "$rm_occ" ]] && continue
    printf '%s' "$rm_occ" | grep -qE '(^|[[:space:]])-[a-zA-Z]*[rR][a-zA-Z]*([[:space:]]|$)|--recursive([[:space:]=]|$)' || continue
    printf '%s' "$rm_occ" | grep -qE '(^|[[:space:]])-[a-zA-Z]*f[a-zA-Z]*([[:space:]]|$)|--force([[:space:]=]|$)' || continue
    # `read -a`, never `for tok in $rm_occ`: word splitting there would also GLOB, and the first
    # target it expanded would be `/*` — the guard would list the root directory and then match
    # nothing. Quotes are stripped by hand because this path never tokenized.
    RM_TOKS=()
    read -r -a RM_TOKS <<<"$rm_occ"
    for rm_tok in "${RM_TOKS[@]}"; do
      rm_tok="${rm_tok//\"/}"
      rm_tok="${rm_tok//\'/}"
      [[ "$rm_tok" == -* ]] && continue
      is_catastrophic_rm_target "$rm_tok" && deny_catastrophic_rm "$rm_tok"
    done
  done <<<"$RM_TEXT_OCC"
fi

# ── Worktree-UNSCOPED pkill/killall of gate processes ─────────────────
# ROOT CAUSE of the 2026-07-26 false-RED epidemic (backlog a0718a5d78b3). Peer sessions were
# SIGKILLing each other's landing gates:
#     pkill -9 -f bats-core/bats                  ← every bats cmdline on this box contains that
#     pkill -f "ship-land.sh --trunk main"
# The desk tied victim gates to actor commands with a 3-5s lag twice over; >=8 broad-pkill events
# across 5 sessions in 24h. Victims mis-read their own SIGKILL as OOM/jetsam (REFUTED: 68% memory
# free, zero memorystatus kills) and propagated that wrong theory into their block reasons.
# These patterns are machine-wide BY CONSTRUCTION, not by accident, so this is a deny and not an
# ask: a correct scoped form exists, and a helper implements it — both are named in the message.
# Scoped forms pass untouched. Kill switch: the whole hook's VALIDATE_BASH_DISABLED=1.
# COMMAND POSITION, not substring: `git commit -m "fix: do not pkill bats"` merely MENTIONS the
# thing. Deciding on raw text is the exact defect this clause exists to stop, one level down (a
# `pkill -f bats` pattern matches peers because it matches TEXT). So the position test runs on a
# quote-STRIPPED copy — killing message bodies — while the target/scope tests below still read the
# ORIGINAL, because that is where the real pattern lives (`pkill -f "bats tests/"`).
#
# A HEREDOC BODY IS DATA TOO (2026-08-12, backlog 15b99887cd5e). Quote-stripping answered
# `git commit -m "…pkill…"` correctly and still convicted the SAME sentence fed through a heredoc,
# because it erases only QUOTED runs and a heredoc body carries no quotes to erase. The splitter
# then turns a literal `(pkill|killall)` in the prose into a fragment BEGINNING with `pkill`, the
# gate opens, and the harvest below lifts `killall) …bats…` back out of the message. Measured while
# committing this clause's own previous fix: the guard blocked its own fix, for the second time —
# which is why the body now comes off FIRST, ahead of the quotes it never had.
#
# The harvest reads that same body-free copy rather than $CMD. It still needs the ORIGINAL QUOTES
# (that is where a real pattern lives), but never the original BODIES: otherwise a correctly scoped
# `pkill -f "bats.*${PWD##*/}"` would be denied by the very commit message describing why it is
# scoped. Text is not execution — and neither is stdin.
CMD_NOHD="$CMD"
if [[ "$HAVE_IS_TRUE_FLAG" == "1" ]] && declare -F strip_heredoc_bodies >/dev/null 2>&1; then
  # Absent library ⇒ $CMD unchanged ⇒ exactly the previous behaviour: an over-block on a heredoc
  # message body, never an under-block. `declare -F` for the same reason rm_argv_scan needs it —
  # hooks/ deploys as per-file symlinks, so a NEW hook can briefly sit beside an OLD lib.
  CMD_NOHD=$(strip_heredoc_bodies "$CMD")
fi
CMD_NOQ=$(printf '%s' "$CMD_NOHD" | sed -e "s/'[^']*'/''/g" -e 's/"[^"]*"/""/g')
if printf '%s' "$CMD_NOQ" | sed 's/[&|()]/;/g' | tr ';' '\n' | sed 's/^[[:space:]]*//' \
     | grep -qE '^(sudo[[:space:]]+)?(pkill|killall)([[:space:]]|$)'; then
  PK_OCCURRENCES=$(printf '%s' "$CMD_NOHD" | grep -oE '(pkill|killall)[^;&|]*' || true)
  while IFS= read -r pk; do
    [[ -z "$pk" ]] && continue
    # ── AN OPTION AFTER THE PATTERN IS NOT AN OPTION (2026-08-09). Target-INDEPENDENT, and it runs
    # BEFORE the gate-program filter below, because the incident that added it named no gate at all.
    #
    # BSD getopt stops at the first non-option argument, and pgrep/pkill then treat every remaining
    # word as an ADDITIONAL PATTERN, OR'd with the first. So `pkill -f "next dev" -P $$` does not
    # mean "my own children matching next dev" — it means "kill anything matching /next dev/ OR /-P/
    # OR /<pid>/", and `-P` is a two-character substring that appears in every fired handoff peer's
    # argv (HANDOFF-PING contains it). Measured: that exact line killed three sessions across two
    # account dirs at 07:38:17Z on 2026-08-09, sparing only the caller's own (pkill excludes its
    # ancestors). The author wrote a scoping flag; the shell delivered a machine-wide pattern.
    #
    # This is ALWAYS a bug — the trailing token is never doing what it reads as — so it is a deny
    # regardless of what is being killed, and it is what makes the `-P` clause in the scope
    # allowlist below SOUND: a `-P` that survives to that test is necessarily in option position.
    # Walk a QUOTE-NEUTRALISED copy, for the same reason the command-position test above does. A
    # quoted pattern may legitimately contain a dash-word — `pkill -f "ship-land.sh --trunk main"`
    # is the guard's OWN documented example — and a whitespace walker over the raw text reads that
    # `--trunk` as a trailing option. Caught by sweeping this check across the repo's 107 tracked
    # kill lines before shipping it: it convicted that line, with the wrong reason. Collapsing each
    # quoted run to one empty token makes a quoted pattern exactly one operand, which is what it is.
    _pk_noq=$(printf '%s' "$pk" | sed -e "s/'[^']*'/''/g" -e 's/"[^"]*"/""/g')
    _pk_bad_opt=$(printf '%s\n' "$_pk_noq" | awk '{
      operand = 0
      for (i = 2; i <= NF; i++) {
        t = $i
        if (t ~ /^-/) {
          if (operand) { print t; exit }
          if (t ~ /^-[FGjPstuUMN]$/) i++     # these consume the next word as their argument
          continue
        }
        operand = 1
      }
    }')
    if [[ -n "$_pk_bad_opt" ]]; then
      deny "Inert flag in a kill: '$_pk_bad_opt' comes AFTER the pattern in '$(echo "$pk" | cut -c1-60)', so pkill/pgrep never parse it as an option. BSD getopt stops at the first operand and every later word becomes an ADDITIONAL PATTERN, OR'd with the first — so this does not narrow the kill, it WIDENS it, and the widening is invisible in the text. Measured 2026-08-09: 'pkill -f \"next dev\" -P \$\$' killed three Claude sessions across two account dirs in one instant, because '-P' matches the argv of every fired handoff peer (HANDOFF-PING contains it); only the caller's own session lived, and only because pkill excludes its own ancestors. Put every flag BEFORE the pattern: 'pkill -f -P \$\$ \"next dev\"' — or verify the selection first with the read-only 'pgrep' form of the same line."
    fi
    # Does this occurrence target a GATE program at all? Otherwise it is none of our business.
    echo "$pk" | grep -qE '(bats|ship-land|postland-verify)' || continue
    # Is it scoped to ONE worktree? Any of: a $PWD-derived expression, a -P (parent-pid) scope,
    # or an explicitly named worktree (a .worktrees/ path or a wt-* directory name).
    # shellcheck disable=SC2016  # $PWD / $(pwd) are LITERALS to match in the command TEXT, by design
    if echo "$pk" | grep -qE '\$PWD|\$\{PWD|\$\(pwd|`pwd|\$\(basename|(^|[[:space:]])-P[[:space:]]|\.worktrees/|(^|[^a-zA-Z0-9])wt-[a-zA-Z0-9]'; then
      continue
    fi
    # …or it names THIS session's own worktree directory literally.
    if [[ -n "${PWD##*/}" ]] && echo "$pk" | grep -qF -- "${PWD##*/}"; then
      continue
    fi
    deny "Worktree-UNSCOPED kill of gate processes blocked: '$(echo "$pk" | cut -c1-60)'. Every bats command line on this box contains '/libexec/bats-core/bats', so this pattern SIGKILLs EVERY concurrent session's landing gate machine-wide, not just yours — the measured root cause of the 2026-07-26 false-RED epidemic (backlog a0718a5d78b3): the victim reports the kill as a gate RED, its item re-blocks, the dispatcher retries, load climbs, more gates die. Use the scoped helper: 'scripts/gate-cleanup.sh --dry-run' to see the selection, then the same without --dry-run. It signals only processes whose cwd is inside THIS worktree, plus their descendants. To scope a pattern by hand, name the worktree in it: pkill -f \"bats.*\${PWD##*/}\"."
  done <<<"$PK_OCCURRENCES"
fi

# ── SELECTION-KEYED kill gate (2026-09-04 — the five husk panes) ─────────────────────────────────
# The clause above is keyed on the SPELLING of three gate programs, and a spelling-keyed guard can
# only enumerate the incidents already paid for (MEMORY: denylist-enumerates-spellings-not-the-class).
# The harm is a property of the SELECTION: on this fleet a Claude session's argv carries its whole
# brief (6-10 KB), so `pkill -f X` matches every sibling whose PROMPT mentions X — measured
# 2026-08-09 (`next dev`, 3 sessions), 2026-08-25 (`cc-await-ping`, 1 session + 3 watchers) and
# 2026-09-04 (`cc-await-ping`, 5 sessions SIGTERMed in 30 s, five panes stranded at a bare shell
# reading "Resume this session with:" — the strand the operator read as failed self-recycles).
# hooks/lib/kill-selection.py asks the REAL pgrep what the kill would select and walks each victim's
# ancestry: OWN (under this session) and UNOWNED (Dock, a hand-started server) pass untouched;
# FOREIGN (another live Claude session, or a process inside one) is denied, with the victims named.
# Dynamic patterns (`$VAR`, `$(…)`) cannot be evaluated statically and ABSTAIN, exactly as today.
# Seams: CC_KILL_SELECTION_GATE=off (kill switch) · CC_KILL_GATE_SELF_PID (own-session root, else the
# nearest `claude` ancestor of this hook) · CC_REGISTRY_DIR (victim → session name). Costs one
# python3 fork, only on a command with pkill/killall/pgrep in command position. Evidence:
# docs/research/husk-panes-pkill-selection-2026-09-04.md.
# The helper is looked up through the symlinked lib dir first and then through the hook's REAL
# path (the checkout), the way smart-bash-allowlist.sh finds its own .py core: on the day this
# landed, install.sh linked only hooks/lib/*.sh, so the live layer had the hook and not its
# helper, and the gate was inert exactly where it was needed. install.sh now links *.py too;
# this fallback is what makes the gate live even across that skew.
KS_PY="$LIB_DIR/kill-selection.py"
if [[ ! -f "$KS_PY" ]]; then
  _ks_real="${BASH_SOURCE[0]}"
  while [[ -L "$_ks_real" ]]; do
    _ks_l=$(readlink "$_ks_real"); [[ "$_ks_l" == /* ]] || _ks_l="$(dirname "$_ks_real")/$_ks_l"; _ks_real="$_ks_l"
  done
  KS_PY="$(cd -P -- "$(dirname -- "$_ks_real")" 2>/dev/null && pwd)/lib/kill-selection.py"
fi
if [[ "${CC_KILL_SELECTION_GATE:-on}" != off && -f "$KS_PY" ]] \
   && command -v python3 >/dev/null 2>&1 \
   && printf '%s' "$CMD_NOQ" | sed 's/[&|()`]/;/g' | tr ';' '\n' | sed 's/^[[:space:]]*//' \
        | grep -qE '^(sudo[[:space:]]+)?(pkill|killall|pgrep)([[:space:]]|$)'; then
  KS_SELF="${CC_KILL_GATE_SELF_PID:-}"
  if [[ -z "$KS_SELF" ]]; then
    _ksp=$$ _ksn=0
    while [[ "$_ksp" -gt 1 && "$_ksn" -lt 12 ]]; do
      _ksc=$(ps -o comm= -p "$_ksp" 2>/dev/null); _ksc=${_ksc##*/}
      [[ "$_ksc" == claude || "$_ksc" == claude-* ]] && { KS_SELF=$_ksp; break; }
      _ksp=$(ps -o ppid= -p "$_ksp" 2>/dev/null | tr -d ' '); _ksn=$((_ksn+1))
      [[ -n "$_ksp" ]] || break
    done
    [[ -n "$KS_SELF" ]] || KS_SELF=$PPID
  fi
  KS_OUT=$(python3 "$KS_PY" "$CMD_NOHD" "$KS_SELF" "${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}" 2>/dev/null || true)
  if [[ -n "$KS_OUT" ]]; then
    IFS=$'\t' read -r _ksk KS_SEG KS_N KS_VICTIMS KS_AP <<<"${KS_OUT%%$'\n'*}"
    if [[ "$_ksk" == FOREIGN ]]; then
      if [[ "$KS_AP" == 1 ]]; then
        KS_REMEDY="To stand down YOUR OWN inbox watcher run 'cc-await-ping --stand-down' — it signals only the watchers claimed on this pane's inbox, by pid, and never a sibling's (a sibling whose watcher dies is DEAF to peer mail until a human types at it)."
      else
        KS_REMEDY="Signal by pid instead ('kill <pid>' from a pgrep you have read), or scope to your own subtree with '-P <pid>' placed BEFORE the pattern."
      fi
      { [ -d "$HOME/.claude/logs" ] || mkdir -p "$HOME/.claude/logs"; printf '{"ts":"%s","sid":"%s","segment":"%s","foreign":%s,"awaitping":%s}\n' "${_P_TS:-}" "${_P_SID:-}" "$(json_escape "$KS_SEG")" "${KS_N:-0}" "${KS_AP:-0}" >> "$HOME/.claude/logs/kill-selection-gate.jsonl"; } 2>/dev/null || true
      deny "Pattern kill blocked — evaluated LIVE, '$KS_SEG' would signal $KS_N process(es) that belong to OTHER Claude sessions: $KS_VICTIMS. On this box a session's argv carries its whole brief, so a -f pattern matches every sibling whose PROMPT mentions the text — measured 2026-08-09 ('next dev', 3 sessions), 2026-08-25 ('cc-await-ping', 1 session + 3 watchers) and 2026-09-04 ('cc-await-ping', 5 sessions SIGTERMed in 30 s, five panes left at a bare shell). $KS_REMEDY Preview any selection first by running the same line with pkill swapped for its read-only twin, pgrep. Kill switch: CC_KILL_SELECTION_GATE=off."
    fi
  fi
fi

# ── EMPTY-SELECTOR kill gate (2026-09-09 — the mass application termination) ─────────────────────
# The gate ABOVE evaluates a selection live, but only when the census verb is pgrep/pkill/killall.
# The 2026-09-09 incident used none of them: a bare `kill` over a pid list computed by a hand-rolled
# `ps -axo pid=,command= | awk …` census. It selected 875 of 878 processes and terminated Kitty,
# Dia, Discord, ~17 Claude Code sessions and most of the user's launchd agents in nine seconds,
# because its awk pattern came from an env-prefix assignment on the PREVIOUS pipeline stage and was
# therefore empty — and an empty selector is a universal one.
#
# lib/is-true-flag.sh :: empty_prefix_expansion_scan decides that statically, with no fork and no
# pattern list: it convicts only when the variable is provably unset AT ITS USE SITE (see the header
# there for the three abstentions). The signal test runs on the quote-STRIPPED copy so a `kill` in a
# commit message body is a string; the emptiness scan runs on the ORIGINAL because that is where the
# pattern lives. Seam: CC_EMPTY_SELECTOR_GATE=off.
# Evidence: docs/research/mass-app-termination-2026-09-09.md.
if [[ "${CC_EMPTY_SELECTOR_GATE:-on}" != off ]] \
   && declare -f empty_prefix_expansion_scan >/dev/null 2>&1 \
   && signals_in_command_position "$CMD_NOQ"; then
  ES_NAME=$(empty_prefix_expansion_scan "$CMD_NOHD" || true)
  if [[ -n "$ES_NAME" ]]; then
    { [ -d "$HOME/.claude/logs" ] || mkdir -p "$HOME/.claude/logs"; printf '{"ts":"%s","sid":"%s","var":"%s"}\n' "${_P_TS:-}" "${_P_SID:-}" "$(json_escape "$ES_NAME")" >> "$HOME/.claude/logs/empty-selector-gate.jsonl"; } 2>/dev/null || true
    deny "Empty-selector kill blocked: \$$ES_NAME is EMPTY where you read it, so this selects EVERY process, not a few. An env-prefix assignment ('$ES_NAME=… cmd') binds only to THAT command's environment — never to the shell — so a \"\$$ES_NAME\" read from any later stage of the pipeline expands to the empty string, and an empty pattern is a UNIVERSAL match: awk's index(\$0,\"\") is 1 on every line, and grep \"\" matches every line. Measured on this machine 2026-09-09 23:55:14Z: exactly this shape selected 875 of 878 processes where the corrected census selects 2, and three SIGTERM waves one second apart terminated Kitty, Dia, Discord, Hammerspoon, ~17 Claude Code sessions and most of the user's launchd agents in nine seconds (the kernel logged 'zsh(66592) deny(1) signal initproc signum:15' — it tried to signal pid 1). FIX: make the assignment reach the shell — '$ES_NAME=…' as its own statement, or 'export $ES_NAME=…', or pass the pattern as a normal awk variable ('local P=…; ps … | awk -v p=\"\$P\"'). Then PREVIEW the selection read-only — run the census alone and count what it returns — before any signal. If you were moving the pattern out of argv to stop a census matching itself, the shell-level assignment does that too; only the env-prefix form does not. Kill switch: CC_EMPTY_SELECTOR_GATE=off."
  fi
fi

# DDL via any mechanism (turso shell, sqlite3, echo|pipe, etc.) — only
# blocked when in DATABASE-COMMAND context. This avoids false positives on
# commit messages that discuss DDL ("fix: block DROP TABLE in migration").
# A command like `echo "DROP TABLE x" | turso db shell` still matches because
# BOTH conditions are true.
if echo "$CMD" | grep -qiE '\b(turso|sqlite3?|psql|mysql|mariadb|libsql|drizzle-kit[[:space:]]+(push|drop|migrate))\b' \
   && echo "$CMD" | grep -qiE '\b(DROP[[:space:]]+TABLE|DROP[[:space:]]+DATABASE|DROP[[:space:]]+INDEX|ALTER[[:space:]]+TABLE|CREATE[[:space:]]+TABLE|TRUNCATE[[:space:]]+TABLE)\b'; then
  deny "DDL blocked — all schema changes must go through Drizzle migrations (pnpm generate). See CLAUDE.md critical rule #1."
fi

# drizzle-kit push bypasses migration history
if echo "$CMD" | grep -qE 'drizzle-kit[[:space:]]+push'; then
  deny "drizzle-kit push bypasses migration history and causes schema drift. Use pnpm generate instead."
fi

# git add -f / --force — read off `git add`'s OWN argv (hooks/lib/is-true-flag.sh ::
# git_add_force_scan). The two conditions used to be independent — "a real -f SOMEWHERE in $CMD"
# AND "the text `git add` SOMEWHERE in $CMD" — which is two different invocations whenever the
# command has more than one clause: `rm -f f.txt && git add f.txt` was denied, and denied with a
# reason naming something it does not do. The same looseness ran the other way and mattered more:
# `git add -fv`, `git add -Af`, `git -C /tmp/x add -f` and `git stage -f` all walked past, because
# the flag had to be spelled as its own bare token and `add` had to be argv[1]. Backlog
# 44750ff72ae7; the equivalence class is not enumerable by regex, so it is not enumerated.
GIT_ADD_SCAN=""
GIT_ADD_SCAN_RC=2
GIT_ADD_PRESENT=0
# Presence gate FIRST, and bash-native so it costs no fork: this runs on every Bash tool call in
# the fleet, and the scan behind it forks python3 (~30 ms). It cannot hide a force-add — a real
# invocation must contain the literal `git` and the literal subcommand (git does not abbreviate
# subcommands), and `stage` is the only other name for `add`.
if [[ "$CMD" == *git* && ( "$CMD" == *add* || "$CMD" == *stage* ) ]]; then
  GIT_ADD_PRESENT=1
  # `declare -F` is not ceremony: hooks/ deploys as per-file symlinks, so a live layer can briefly
  # hold a NEW validate-bash.sh beside an OLD lib. Absent function → text path, never a crash.
  if [[ "$HAVE_IS_TRUE_FLAG" == "1" ]] && declare -F git_add_force_scan >/dev/null 2>&1; then
    GIT_ADD_SCAN=$(git_add_force_scan "$CMD")
    GIT_ADD_SCAN_RC=$?
  fi
fi
if [[ "$GIT_ADD_PRESENT" == "1" && "$GIT_ADD_SCAN_RC" == "0" ]]; then
  while IFS=$'\t' read -r ga_force ga_tok; do
    [[ "$ga_force" == "1" ]] || continue
    deny "git add $ga_tok blocked — gitignored files are intentionally excluded. Force-adding bypasses .gitignore protection. This reads git add's own argv: a -f belonging to another command on the same line is not this rule."
  done <<<"$GIT_ADD_SCAN"
elif [[ "$GIT_ADD_PRESENT" == "1" ]]; then
  # UNCLEAR (python3 absent / unparseable) or VALIDATE_BASH_LEGACY=1 → the pre-argv text rule,
  # unchanged. It over-blocks a sibling clause's -f, which is the safe direction and exactly what
  # shipped; it is a rollback of the PARSER, never a re-opening of the bypass. Reached only behind
  # the presence gate, so a command with no `git add` in it no longer pays check_real_flag's fork.
  if check_real_flag "--force" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then
    deny "git add --force blocked — gitignored files are intentionally excluded. Force-adding bypasses .gitignore protection."
  fi
  if check_real_flag "-f" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then
    deny "git add -f blocked — gitignored files are intentionally excluded. Force-adding bypasses .gitignore protection."
  fi
fi

# --no-verify bypasses pre-commit hooks (CLAUDE.md critical rule)
# argv-aware: recognises that `--no-verify` inside a quoted -m / -F message
# body is not a real flag to git.
if check_real_flag "--no-verify"; then
  deny "--no-verify blocked — bypasses pre-commit hooks. Fix the underlying hook failure instead. See CLAUDE.md critical rule #2."
fi

# --no-gpg-sign also bypasses signing policy
if check_real_flag "--no-gpg-sign"; then
  deny "--no-gpg-sign blocked — bypasses commit signing policy. See CLAUDE.md git-safety rules."
fi

# git commit -n short form of --no-verify (head-aware regex). `-n` is meaningful
# only when preceded by `git commit` (or git commit --amend, etc.). Cannot use
# is_true_flag since `-n` is common on many tools (cat -n, sed -n, head -n).
if echo "$CMD" | grep -qE 'git([[:space:]]+-[a-zA-Z]+[[:space:]]+[^[:space:]]+)*[[:space:]]+commit\b[^|&;]*[[:space:]]-n\b'; then
  deny "git commit -n blocked — short form of --no-verify, bypasses pre-commit hooks. See CLAUDE.md critical rule #2."
fi

# ── the identity GATE's own escape hatches (2026-08-08) ───────────────
# The rules above refuse `--no-verify` and `git commit -n` — the escape an agent reaches for FIRST
# when githooks/pre-commit refuses it. A red-team found that the two which actually WORK were both
# unblocked and documented as supported overrides three lines from the refusal message, so an
# agent under "🔧 never yields" was being steered straight at them:
#
#   CC_GIT_IDENTITY_OWNER=x git commit …        takes the repo OUT OF SCOPE, so the gate exits 0
#                                               without ever reading the identity. Silent.
#   git config --local cc.identity.exempt "…"   exempts the repo — and from a linked worktree that
#                                               writes the SHARED config, exempting ~200 at once.
#
# The vars are now sealed behind CC_GIT_IDENTITY_TEST=1 (the suite sets it, production does not),
# so the single-var form is already inert. This blocks the two-var form and the exemption: a
# bypass that merely also has to disable the seal is still a bypass, and an exemption is a
# DECISION about how the operator's commits are attributed, which is theirs to make.
if printf '%s' "$CMD" | grep -qE '\bCC_GIT_IDENTITY_(TEST|EMAIL|OWNER|HOOK)='; then
  deny "CC_GIT_IDENTITY_* assignment blocked — these are the identity gate's TEST seams, not a route past it. Setting OWNER takes the repo out of scope so the gate never reads the identity at all; setting EMAIL widens the allowlist. If a commit is being refused, the identity is genuinely wrong — run the cure the hook printed. To run the suite, invoke bats (it sets the sentinel itself); never set these by hand."
fi
# WRITES only. The first cut matched the key anywhere after `config`, so `--get cc.identity.exempt`
# — the way you INSPECT an exemption, and what the sweep itself does — was denied. A guard that
# blocks reading the thing it guards makes the state unauditable, which is the opposite of the
# point. Same read-form exclusion the identity-write clause below uses, and a write is recognised
# the same way: the key must be FOLLOWED BY A VALUE.
if printf '%s' "$CMD" | grep -qE '\bconfig\b' \
   && ! printf '%s' "$CMD" | grep -qE '\-\-(get|get-all|get-regexp|list|unset|unset-all|remove-section)\b' \
   && printf '%s' "$CMD" | grep -qE '\bcc\.identity\.exempt[[:space:]]+[^[:space:]]'; then
  deny "cc.identity.exempt write blocked — an exemption declares that a repo's commits SHOULD carry a non-default address. That is the operator's call, not a way to clear a refusal. From a linked worktree 'git config --local' writes the SHARED .git/config, so it exempts every worktree of the repo at once (~200 here). If the identity is simply wrong, fix the identity; if the repo genuinely needs a project address, ask."
fi

# ── git identity write that can collapse into the CURRENT repo ────────
# 2026-08-05 incident: `git -C "" config user.email t@t` is a DOCUMENTED NO-OP on the -C — it
# does NOT change directory (verified live on git 2.54.0), so the write lands in whatever repo
# is cwd. claude-infrastructure is one bare repo with ~100 linked worktrees that SHARE a single
# .git/config, so one such line re-authors every session on the box: 9 mis-attributed commits
# here, 214 on reso. Local scope beats global and `t@t` matches no GitHub account, so the only
# true repair is rewrite+force-push across 213 live worktrees — i.e. unrepairable after the fact.
# Prevention is the whole game. Evidence: docs/research/git-identity-leak-2026-08-05.md §D.
#
# Why THIS hook: the corpus half of the leak is a tree-wide lint over source. Reso has no leaky
# source at all — it was poisoned by an agent hand-typing the same line in an adversarial repro
# (the advV/advJ rows approved into its settings.local.json:470-476). A source lint is
# structurally blind to that. A PreToolUse hook is the only thing that sees it.
#
# Why the SHAPE and not the spelling: this hook reads the command BEFORE expansion, so
# `-C "$SOMEDIR"` is statically undecidable — it is empty exactly when the accident happens, and
# never when you test it. Matching a literal `-C ""` would be a denylist of one spelling that
# misses every real occurrence (memory: denylist-enumerates-spellings-not-the-class). So the rule
# is the research doc's lint rule 2 applied to argv: an identity WRITE must name its target with
# something that CANNOT expand to nothing. `-C /tmp/x`, `-C "$tmp/repo"` and `-C "${r:?}"` pass;
# `-C "$1"`, `-C "$REPO"`, `-C ""`, `-C "$(mktemp -d)"` and a bare no-`-C` write do not.
#
# `cd <target> &&` counts as naming the target, but is held to the SAME test — and that is a
# correction to the research doc's own §Fixes table, measured here: **`cd "" ` SUCCEEDS** (rc 0,
# cwd unchanged). So the prescribed `cd "$repo" || exit 1` idiom guards a *nonexistent* path and
# not an *empty* one — against the empty variable it is inert, and `&&` short-circuiting never
# fires. Both collapse paths therefore need the identical literal-remainder test.
#
# NOT matched, by construction: reads (`--get*`, `--list`, `-l`), the `--unset*` repair this
# incident actually needed (a guard that denies its own fix is the -rf lesson), explicitly-scoped
# writes (`--global`/`--system`/`--file`/`--blob` name their own target — no cwd to collapse
# into), and the transient `git -c user.email=… commit` form, which is lowercase `-c`, is not a
# `config` subcommand, and cannot persist at all — it is the recommended shape.

# Every `$…` below is a LITERAL to be matched, never an expansion to be performed — that is the
# whole point of a guard that reads commands before the shell does. Single quotes are load-bearing.
# shellcheck disable=SC2016
# _gid_literal_survives <token> — 0 when the token cannot expand to nothing.
# Delete-then-match, never widen: strip quotes, delete every expansion, and ask whether any
# LITERAL text is left. `"$tmp/repo"` leaves `/repo` (safe); `"$1"` and `""` leave nothing.
_gid_literal_survives() {
  local t="$1"
  # `${v:?}` / `${v:?msg}` aborts on empty rather than expanding to it — the doc's own
  # prescribed helper guard. Treat it as naming a target even though it is all-expansion.
  case "$t" in *':?'*) return 0 ;; esac
  t="$(printf '%s' "$t" | tr -d "\"'")"
  # A command substitution containing whitespace is TORN APART by the positional walk, so the
  # target arrives as the fragment `$(mktemp` and the balanced-form deletion below can never
  # match it — it would survive as literal text and pass. Any substitution marker at all means
  # the value is computed at runtime and can come back empty: `$(mktemp -d)` on a full disk is
  # precisely the unchecked-mktemp leak site the research doc lists.
  case "$t" in *'$('*|*'`'*) return 1 ;; esac
  t="$(printf '%s' "$t" | sed -E 's/\$\([^)]*\)//g; s/`[^`]*`//g; s/\$\{[^}]*\}//g; s/\$[A-Za-z_][A-Za-z0-9_]*//g; s/\$[0-9@*#?-]//g')"
  [ -n "$t" ]
}

# _gid_target_of <clause> — prints the token that NAMES the write target, empty if none.
# Positional walk, not a regex: only argv position can tell a real `-C` from the same two
# characters inside a quoted value. `-C` wins over `--git-dir=`, which wins over a governing `cd`.
_gid_target_of() {
  local tok prev="" c="" g="" d=""
  set -f  # a command containing `*` must not glob against the cwd during the walk
  for tok in $1; do
    case "$prev" in
      -C) [ -n "$c" ] || c="$tok" ;;
      cd) [ -n "$d" ] || d="$tok" ;;
    esac
    case "$tok" in --git-dir=*) [ -n "$g" ] || g="${tok#--git-dir=}" ;; esac
    prev="$tok"
  done
  set +f
  printf '%s' "${c:-${g:-$d}}"
}

# Fast pass-through, BUILTIN and fork-free. This hook runs on every Bash tool call in the fleet
# and the clause scan below costs one fork per clause, so the common case (no identity key
# anywhere in the command) must not reach it at all — the same measured concern that replaced
# `$(cat)` with `read -d ''` at the top of this file (~6 ms per fork, ~18% of a 163 ms chain).
if [[ "$CMD" == *user.email* || "$CMD" == *user.name* ]]; then
# Split on `;` and `|` so a compound command cannot be exonerated by a sibling clause (the
# per-target lesson the rm scan below already learned) — but NEVER on `&&`, which is what
# GOVERNS the fragment: splitting there would hide the `cd … &&` and convict a guarded write.
# `tr` pads the replacement set with its last char, so one `\n` maps BOTH delimiters — spelling it
# '\n\n' is the same operation with a duplicate shellcheck rightly flags (SC2020).
GID_CLAUSES="$(printf '%s' "$CMD" | tr ';|' '\n')"
while IFS= read -r gid_clause; do
  printf '%s' "$gid_clause" | grep -qE 'git\b.*\bconfig\b.*\buser\.(email|name)\b' || continue
  # Reads, the repair, and explicitly-scoped writes are never blocked.
  printf '%s' "$gid_clause" | grep -qE '\-\-(get|get-all|get-regexp|get-urlmatch|list|unset|unset-all|remove-section|rename-section|global|system|file|blob)\b' && continue
  printf '%s' "$gid_clause" | grep -qE '[[:space:]]-(l|e)([[:space:]]|$)' && continue
  # A bare `git config user.email` READS. Only a key FOLLOWED BY A VALUE writes.
  printf '%s' "$gid_clause" | grep -qE '\buser\.(email|name)[[:space:]]+[^[:space:]]' || continue

  gid_target="$(_gid_target_of "$gid_clause")"
  if [ -z "$gid_target" ]; then
    deny "git identity write with no target blocked — 'git config user.email/name <value>' writes to whatever repo is CURRENT. claude-infrastructure is one bare repo whose ~100 linked worktrees SHARE a single .git/config, so this re-authors every session on the machine (2026-08-05: 9 mis-attributed commits here, 214 on reso; unrepairable without a rewrite+force-push across 213 live worktrees). Use the transient form, which cannot persist: git -c user.email=you@example.com -c user.name='Your Name' commit … — or name the repo with a literal path: git -C /tmp/your-fixture config user.email … . To read, --get; to clean up, --unset-all; to set your real global identity, --global."
  fi
  if ! _gid_literal_survives "$gid_target"; then
    deny "git identity write to an all-expansion target blocked: -C '$gid_target'. That argument is entirely a variable/substitution, so it is EMPTY exactly when the accident happens — and 'git -C \"\"' is a documented NO-OP that does not change directory, dropping the write into the CURRENT repo instead (verified live, git 2.54.0). That is the 2026-08-05 leak: ~100 linked worktrees share one .git/config, so one such line re-authored 9 commits here and 214 on reso. 'cd \"\"' does NOT save you either — it exits 0 and stays put, so '&&' never short-circuits. Give the target a literal segment that cannot vanish (git -C \"\$tmp/repo\" config … ), assert it first (git -C \"\${dir:?repo path required}\" config … ), or best, use the transient form that cannot persist at all: git -c user.email=… -c user.name=… commit … ."
  fi
done <<<"$GID_CLAUSES"
fi

# ── FF-GATE BEGIN — ungated advance of the SHARED CHECKOUT (backlog 8c6606b6f048) ────────────────
# The class was DETECTED and enforced by NOTHING. `scripts/deploy-parity-assert.sh` (third leg,
# :755-830) scores an ungated advance UNGATED *after the fact*, and `.claude/commands/ship.md:120`
# states the doctrine in prose — but prose advises and a post-hoc check reports; neither can stop
# the advance. Measured over the shared checkout's full reflog window (2026-08-01 → 2026-08-17):
# 42 `merge origin/main` + 8 `pull --ff-only …` ungated advances against the sanctioned lane.
#
# WHY THE ADVANCE IS THE HARM: `~/.claude/{hooks,commands,scripts,bin,skills}` are real directories
# of PER-FILE symlinks, so a bare fast-forward advances the FILES and creates NO link for any newly
# tracked file — the feature lands absent, not stale, and every `[ -f x ]` / `command -v` consumer
# guard silently skips it. It also skips the green-stamp gate entirely. And it leaves live and
# checkout in PERFECT agreement, so both parity legs above it are structurally blind to it.
#
# WHY THIS HOOK IS THE CHOKEPOINT, verified rather than assumed: of the three advance paths
# inventoried in docs/research/land-architecture-100p-2026-08-10/E-live.md §1.2, path A is the
# sanctioned launchd tick, path C (deploy-now.sh's own raw ff) was deleted by 5626e682f, and the
# surviving ungated path is **B — an agent session typing the command**, recorded there as a
# verbatim tool call (`git pull --ff-only -q origin main`, session d3b1290e). No tracked script
# contains that string. An agent-typed Bash call is exactly what PreToolUse sees, and nothing else
# does (MEMORY.md enforcement-must-live-at-the-chokepoint: gate the event that IS the act).
#
# THE DISCRIMINATOR IS REUSED, NOT INVENTED — deploy-parity-assert.sh:813-822, proven in the field:
# deploy-live.sh resolves its target with rev-parse BEFORE merging (`merge --ff-only "$TARGET"`),
# so a sanctioned advance always names a resolved OBJECT NAME. Every ungated path either names a
# REF or is not a merge at all. So the rule is structural, not a list of spellings
# (MEMORY.md denylist-enumerates-spellings-not-the-class): in the shared checkout, a `git merge`
# whose target is not an object name, and any `git pull`, is an ungated advance. `origin/main`,
# `origin main`, `@{u}`, a branch name and a bare `git merge` are all the same member of one class.
#
# SCOPE, deliberately narrow on both axes:
#   · REPO — only the shared checkout itself (and paths beneath it). A linked worktree is a
#     DIFFERENT directory, so the ordinary `git pull --ff-only` a session runs in its own worktree
#     is untouched by construction — that is the innocent population, and a guard that fired on it
#     would be worse than none (MEMORY.md alarm-polarity-and-attention-budget).
#   · MECHANISM — merge/pull only. `reset`/`checkout` also appear in the reflog, but every innocent
#     spelling of `git reset` outnumbers the guilty one and no predicate here separates them; that
#     member is named and NOT claimed rather than guessed at. `git fetch` is untouched: refreshing
#     refs is not advancing HEAD, and it is what the operator wants before deploying.
# Fails OPEN on anything undecidable (an all-expansion path or target, an unresolvable directory):
# this hook reads commands BEFORE the shell expands them, and a false deny in the deploy lane would
# strand the very sessions that keep the live layer converged.
#
# The BEGIN/END markers above and below are load-bearing: tests/validate-bash-ff-gate.bats builds
# its mutation control by deleting exactly this span, so a green suite credits this block and not
# the fixture (MEMORY.md control-must-replay-the-real-artifact, per-site-mutation-attributes-coverage).
#
# Builtin fast pass-through, fork-free — this hook runs on EVERY Bash tool call in the fleet.
if [[ "$CMD" == *merge* || "$CMD" == *pull* ]]; then
FFG_SHARED="${CC_SHARED_CHECKOUT:-$HOME/Development/claude-infrastructure}"
FFG_CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
[[ -n "$FFG_CWD" ]] || FFG_CWD="$PWD"

# _ffg_scan <clause> — positional walk setting FFG_SUB / FFG_TGT / FFG_DIR / FFG_CD. Only argv
# POSITION distinguishes the git SUBCOMMAND `merge` from the same eight characters inside
# `git log --merges`, `git branch --merged`, or a commit message — which is why this is a walk and
# not a regex, the same lesson _gid_target_of above already encodes.
#
# It returns through GLOBALS rather than a delimited line, and that is a correction, not a style
# choice: the first build printed "sub\ttgt\tdir" and read it back under `IFS=$'\t'`. Tab is an IFS
# WHITESPACE character, so bash collapses runs of it and drops leading ones — a cd-only clause,
# whose first three fields are empty, arrived as ONE field and landed in `sub`. Globals also mean
# no command substitution, i.e. no subshell fork per clause on a hook that runs on every Bash call.
_ffg_scan() {
  # IFS pinned LOCALLY: the walk's word-splitting must not inherit whatever a caller left set.
  local tok prev="" c="" g="" d="" sub="" tgt="" state=pre IFS=$' \t\n'
  set -f  # a command containing `*` must not glob against the cwd during the walk
  for tok in $1; do
    case "$prev" in
      -C) [ -n "$c" ] || c="$tok"; prev="$tok"; continue ;;  # `-C <dir>` — value never a subcommand
      -c) prev="$tok"; continue ;;                            # `git -c k=v …` — same
      # A `cd` GOVERNS only what comes after it, so one found past the subcommand
      # (`git merge x && cd /tmp`) is not this command's directory and is not recorded.
      cd) [ -n "$d" ] || [ -n "$sub" ] || d="$tok" ;;
    esac
    case "$tok" in --git-dir=*) [ -n "$g" ] || g="${tok#--git-dir=}" ;; esac
    # A chain operator ENDS the current command. With the answer already in hand, stop; otherwise
    # rewind to `pre` so the NEXT git in the chain gets a full walk of its own — without this,
    # `git fetch && git merge origin/main` parked in state `done` and the merge was never seen.
    case "$tok" in
      '&&'|'||'|'&') if [ -n "$sub" ]; then break; else state=pre; prev="$tok"; continue; fi ;;
    esac
    case "$state" in
      pre)  case "$tok" in git|*/git) state=opts ;; esac ;;
      opts) case "$tok" in
              -*) ;;                                  # a git GLOBAL option, keep looking
              merge|pull) sub="$tok"; state=args ;;
              *) state=pre ;;                         # another subcommand — rewind, keep walking
            esac ;;
      args) case "$tok" in -*) ;; *) [ -n "$tgt" ] || tgt="$tok" ;; esac ;;
    esac
    prev="$tok"
  done
  set +f
  FFG_SUB="$sub"; FFG_TGT="$tgt"; FFG_DIR="${c:-$g}"; FFG_CD="$d"
}

# _ffg_resolve <named-dir> — canonical directory the clause would act in, empty when undecidable.
_ffg_resolve() {
  local n="$1"
  [ -n "$n" ] || n="$FFG_CWD"
  case "$n" in *'$'*|*'`'*) return 0 ;; esac   # computed at runtime — undecidable, fail open
  n="$(printf '%s' "$n" | tr -d "\"'")"
  # `\~` and `\~/*` are case PATTERNS matched literally — a `cd ~/…` typed by an agent reaches this
  # hook unexpanded, so the tilde has to be expanded here or the path resolves nowhere.
  case "$n" in \~) n="$HOME" ;; \~/*) n="$HOME/${n#\~/}" ;; esac
  ( cd "$FFG_CWD" 2>/dev/null && cd "$n" 2>/dev/null && pwd -P ) || true
}

# Split on `;` and `|` but NEVER on `&&`: `cd <repo> && git merge …` is one act, and splitting
# there would drop the `cd` that names the target — the same reasoning the identity walk states.
FFG_CLAUSES="$(printf '%s' "$CMD" | tr ';|' '\n')"
while IFS= read -r ffg_clause; do
  # Cheap builtin filter — a clause with neither a `git` nor a `cd` in it can decide nothing.
  case "$ffg_clause" in *git*|*cd*) ;; *) continue ;; esac
  _ffg_scan "$ffg_clause"
  ffg_sub="$FFG_SUB"; ffg_tgt="$FFG_TGT"; ffg_dir="$FFG_DIR"; ffg_cd="$FFG_CD"
  # A `cd` PERSISTS for the rest of the tool call, so it governs later LINES too — and the
  # measured incident is exactly that shape: `cd /Users/…/claude-infrastructure` on one line,
  # `git pull --ff-only -q origin main` on the next (E-live.md §1.2 path B, verbatim). Tracking it
  # only within a single `&&` clause would have missed the one command this guard exists to stop.
  if [ -n "$ffg_cd" ]; then
    ffg_moved="$(_ffg_resolve "$ffg_cd")"
    [ -n "$ffg_moved" ] && FFG_CWD="$ffg_moved"
  fi
  [ -n "$ffg_sub" ] || continue

  if [ "$ffg_sub" = merge ]; then
    ffg_bare="$(printf '%s' "$ffg_tgt" | tr -d "\"'")"
    # An all-expansion target is deploy-live.sh's own spelling (`merge --ff-only "$TARGET"`) and
    # appears nowhere in the measured ungated population, every member of which names a literal
    # ref. Undecidable here, and allowing it keeps the sanctioned lane's exact line runnable.
    case "$ffg_bare" in *'$'*|*'`'*) continue ;; esac
    # Hex-only and >= 7 chars ⇒ an object name, i.e. the sanctioned resolved-SHA advance. Every ref
    # spelling this repo uses carries a character outside [0-9a-f], so a ref cannot launder as one.
    case "$ffg_bare" in
      ""|*[!0-9a-f]*) ;;
      *) [ "${#ffg_bare}" -ge 7 ] && continue ;;
    esac
  fi

  ffg_at="$(_ffg_resolve "$ffg_dir")"
  [ -n "$ffg_at" ] || continue
  ffg_shared="$( cd "$FFG_SHARED" 2>/dev/null && pwd -P )" || ffg_shared=""
  [ -n "$ffg_shared" ] || continue
  case "$ffg_at" in
    "$ffg_shared"|"$ffg_shared"/*) ;;
    *) continue ;;                              # a worktree or another repo — never this guard's business
  esac

  deny "Ungated advance of the SHARED CHECKOUT blocked: 'git $ffg_sub${ffg_tgt:+ $ffg_tgt}' in $ffg_at. That fast-forward advances the FILES but creates no symlinks — ~/.claude/{hooks,commands,scripts,bin,skills} are per-file symlinks, so every newly tracked file lands UNLINKED and silently does nothing (hooks/lib/cc-interactive.sh shipped that way and disabled an operator hold) — and it skips the green-stamp gate, so unverified trunk goes live for the whole fleet. It is also invisible afterwards: it leaves live and checkout in perfect agreement, which is why deploy-parity-assert's provenance leg has to read the reflog to see it at all (42 merge origin/main + 8 pull --ff-only ungated advances, 2026-08-01..08-17). Run the one sanctioned advance instead — it is green-gated and runs install.sh, which is what actually creates the links: bash $ffg_shared/scripts/deploy-live.sh . (--force is the deliberate escape hatch; 'git fetch' to refresh refs is fine and is not what this blocks; the same command in YOUR worktree is untouched.)"
done <<<"$FFG_CLAUSES"
fi
# ── FF-GATE END ─────────────────────────────────────────────────────────────────────────────────

# ── PERMHARVEST-APPLY BEGIN ─────────────────────────────────────────────────────────────────────
# `cc-permission-harvest --apply` WRITES THE PERMISSION ALLOWLIST, and an agent must never run it.
#
# WHY THIS IS A HOOK AND NOT THE TOOL'S OWN ENV CHECK. The tool does carry one (CLAUDECODE /
# CLAUDE_CODE_SESSION_ID), and it is a courtesy message, not a guard: an agent can unset the very
# variables it reads, in the same command line, so the check is an honour system administered by
# the party it constrains. A PreToolUse hook precedes rules and the classifier and cannot be unset
# from inside a session, so THIS is the chokepoint (§10 B1-4; the CC_PERMHARVEST_ALLOW_IN_SESSION
# override the first design carried was deleted for the same reason — an override is the guard
# handing back the key).
#
# WHY THE PREDICATE IS ARGV MEMBERSHIP AND NOT A REGEX ON THE COMMAND. `grep 'cc-permission-harvest
# --apply'` is a claim about SPELLING, and every spelling is one space, one `$VAR`, one absolute
# path or one interpreter prefix away from false: `python3 ~/.claude/bin/cc-permission-harvest
# --apply`, `CONFIRM=1 cc-permission-harvest  --apply`, `cc-permission-harvest --apply --only X`.
# So the command is tokenized (shlex, the same parser rm_argv_scan and git_add_force_scan use) and
# the question is asked of each CLAUSE's argv: does any token's BASENAME equal the tool, and does a
# token in the SAME clause spell --apply. Both halves must live in one clause —
# `cc-permission-harvest --check && echo --apply` is two invocations and is not this rule. A
# quoted string is ONE token, so `git commit -m "deny cc-permission-harvest --apply"` is not this
# rule either: the rm guard's first cut blocked its own fix from being committed, and that lesson
# is not re-learned here. Heredoc bodies are stripped first (the lib's awk, no fork), so a doc
# written through `cat <<EOF` is text too.
#
# THE REACH, stated so nobody has to re-derive it. Beyond the one-clause argv rule, four bounded
# extensions, every one keyed on the HEAD of the clause and every one over-blocking only in the
# safe direction: a string handed to `bash -c` / `sh -c` / `eval` IS argv one level down and is
# re-read as such (two levels, the deepest spelling anyone types); an interpreter one-liner
# (`python3 -c`, `perl -e`, …) whose string carries both literals is read as the invocation it is;
# `xargs cc-permission-harvest` fed by any clause that spells --apply is the same invocation
# assembled from stdin; and a heredoc BODY feeding a shell or interpreter head is code, so that
# shape is refused on the presence gate alone. A script written to disk and then run is out of
# reach of any argv gate and is not pretended otherwise.
#
# INERT HEADS ARE SKIPPED (echo/printf/cat/tee/:/true) because a clause whose head only PRINTS is
# not an argv for the tool at all — writing about the command in a session is not running it.
#
# UNCLEAR FAILS SAFE. python3 absent or shlex refusing the string (an unbalanced quote) drops to a
# whitespace split of each leaf, which over-blocks a quoted body — the safe direction, and the
# message says how to phrase a quotation. The presence gate is builtin and fork-free: this hook runs
# on EVERY Bash tool call in the fleet, and only a command carrying both literals pays the fork.
#
# 🚨 THE PRESENCE GATE IS ASKED OF A QUOTE-STRIPPED COPY, AND THAT IS THE WHOLE ARM (fixed
# 2026-09-09). Everything above argues that a SPELLING test is the wrong predicate — and then the
# arm was ENTERED by exactly such a test, `[[ "$CMD" == *cc-permission-harvest* && *--apply* ]]`
# over the RAW command. Bash removes quotes before exec; this hook never did. So any quoting that
# split either literal in the raw text skipped the tokenizer, the fail-safe fallback and the deny,
# and the documented "hard stop" was two characters away from open. MEASURED, all eight reaching
# `decision=none` while a PATH stub proved bash still ran the tool with `--apply` in argv:
#   cc-permission-har''vest --apply     cc-permission-har""vest --apply
#   cc-permission-harve\st --apply      cc-permission-harvest --ap"p"ly
#   cc-permission-harvest --app'l'y     X=--apply; cc-permission-harvest $X
#   $'cc-permission-harvest' --apply    cc-permission-harvest $"--apply"
# and the composed `env -u CLAUDECODE -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_ENTRYPOINT CONFIRM=1
# cc-permission-har''vest --apply`, which also strips the tool's own courtesy env check — with the
# hook skipped there was nothing left at all.
# PHA_PROBE deletes `'`, `"`, `\` and `$` from a COPY (builtin substitution, still fork-free) so
# every spelling above folds back onto the two literals. It is a PRE-FILTER only: it may over-admit
# (`--ap$ply` folds too), and over-admitting costs one fork and then a PASS from the tokenizer.
# RESIDUE, stated rather than discovered later: literals assembled from two variables
# (`A=--ap; B=ply; … $A$B`) survive it, as does a script written to disk and then run. No argv gate
# reaches either. `--check`/`--falsify`/`--json` runs are untouched: none spells `--apply`.
# One substitution per character, not a bracket class: `[\'\"\\$]` inside double quotes does not
# survive bash's own quote removal (it dies at "unexpected EOF looking for matching `\"'"). A
# FUNCTION, not a `$(...)`, so the gate stays fork-free on every Bash call in the fleet.
pha_flatten() {
  PHA_FLAT="$1"
  PHA_FLAT="${PHA_FLAT//\'/}"
  PHA_FLAT="${PHA_FLAT//\"/}"
  PHA_FLAT="${PHA_FLAT//\\/}"
  PHA_FLAT="${PHA_FLAT//\$/}"
}
pha_flatten "$CMD"
PHA_PROBE="$PHA_FLAT"
if [[ "$PHA_PROBE" == *cc-permission-harvest* && "$PHA_PROBE" == *--apply* ]]; then
  PHA_SRC="$CMD"
  if [[ "$HAVE_IS_TRUE_FLAG" == "1" ]] && declare -F strip_heredoc_bodies >/dev/null 2>&1; then
    PHA_SRC="$(strip_heredoc_bodies "$CMD")"
  fi
  PHA_VERDICT="UNCLEAR"
  if command -v python3 >/dev/null 2>&1; then
    PHA_VERDICT="$(CMD="$PHA_SRC" python3 - <<'PY' 2>/dev/null
import os
import shlex

TOOL = "cc-permission-harvest"
SENTINEL = "HEREDOC_INPUT_SENTINEL"          # what strip_heredoc_bodies leaves where `<<EOF` was
INERT = {"echo", "printf", "cat", "tee", "true", ":"}
SHELLS = {"bash", "sh", "zsh", "dash", "ksh", "eval"}
INTERPS = {"python", "python2", "python3", "perl", "ruby", "node", "php", "osascript", "expect"}
# Newline is PUNCTUATION here, not whitespace: to bash it ends a command, and a tokenizer that
# swallowed it would let `echo x<newline>cc-permission-harvest --apply` inherit the inertness of echo.
# `#` is never a comment: to bash `a#b` is one word, and a comment rule would hide what follows.
PUNCT = "();<>|&\n"


def tokens(src):
    lex = shlex.shlex(src, posix=True, punctuation_chars=PUNCT)
    lex.whitespace = " \t\r"
    lex.whitespace_split = True
    lex.commenters = ""
    return list(lex)


def is_sep(t):
    return t in ("|", "||", "&&", ";", ";;", "&", "(", ")") or ("\n" in t and t.strip(PUNCT) == "")


def clauses(toks):
    out = [[]]
    for t in toks:
        if is_sep(t):
            out.append([])
        else:
            out[-1].append(t)
    return [c for c in out if c]


def strip_env(argv):
    i = 0
    while i < len(argv) and "=" in argv[i] and not argv[i].startswith("-"):
        name = argv[i].split("=", 1)[0]
        if name and (name[0].isalpha() or name[0] == "_") and all(ch.isalnum() or ch == "_" for ch in name):
            i += 1
        else:
            break
    return argv[i:]


def unsigil(t):
    # A LEADING DOLLAR IS BASH QUOTING SHLEX DOES NOT KNOW. posix shlex strips the quotes of the
    # bash forms dollar-single-quote and dollar-double-quote but KEEPS the sigil, so
    # dollar-quoted cc-permission-harvest tokenizes to a token whose basename is
    # "$cc-permission-harvest" and no comparison here matches it. Bash removes the sigil before
    # exec, so every comparison below is asked of the token bash would actually hand the kernel.
    return t[1:] if t[:1] == "$" else t


def is_apply(src, depth=0):
    """True iff some clause of `src` is an invocation of the tool carrying --apply."""
    for argv in clauses(tokens(src)):
        argv = strip_env(argv)
        if not argv:
            continue
        flat = [unsigil(t) for t in argv]
        head = os.path.basename(flat[0])
        if head in INERT:
            continue
        # AN UNRESOLVED DOLLAR IN A CLAUSE THAT NAMES THE TOOL IS NOT A PASS. shlex is not bash and
        # cannot know what a variable becomes: the spelling X=--apply then the tool then dollar-X
        # tokenizes to an argv with NO --apply in it, and was MEASURED reaching decision=none while
        # bash ran the tool with --apply in argv. The presence gate has ALREADY established that
        # both literals appear somewhere in this command, so the only open question is which token
        # carries them, and a token this parser cannot resolve is refused rather than guessed.
        # SCOPED to a clause that mentions the tool as a substring (an interpreter path counts) or
        # whose HEAD is itself a variable: a dollar anywhere else belongs to somebody elses command
        # and stays a PASS, so a grep of a variable path beside a --check run is not collateral.
        # Inert heads are skipped above, so quoting the command inside an echo still passes.
        if any("$" in t for t in argv) and (any(TOOL in t for t in flat) or "$" in argv[0]):
            return True
        tool = any(os.path.basename(t) == TOOL for t in flat)
        if tool and any(t == "--apply" or t.startswith("--apply=") for t in flat):
            return True
        if head == "xargs" and tool and "--apply" in src:
            return True
        if head in SHELLS and depth < 2:
            for t in flat[1:]:
                if TOOL in t and "--apply" in t and is_apply(t, depth + 1):
                    return True
        if head in INTERPS and any(TOOL in t and "--apply" in t for t in flat[1:]):
            return True
        if (head in INTERPS or head in SHELLS) and any(SENTINEL in t for t in flat):
            return True
    return False


try:
    print("DENY" if is_apply(os.environ.get("CMD", "")) else "PASS")
except ValueError:
    print("UNCLEAR")
PY
)"
  fi
  PHA_DENY=0
  case "$PHA_VERDICT" in
    PASS) ;;
    DENY) PHA_DENY=1 ;;
    *)
      # No argv available. Leaves on `;`/`|`/`&`/newline (builtin substitution, fork-free), each
      # whitespace-split with IFS pinned and globbing off, quotes peeled off the ends of tokens.
      PHA_LEAVES="${PHA_SRC//;/$'\n'}"
      PHA_LEAVES="${PHA_LEAVES//|/$'\n'}"
      PHA_LEAVES="${PHA_LEAVES//&/$'\n'}"
      while IFS= read -r pha_leaf; do
        # The leaf test folds quoting the same way the presence gate does — a fallback that only
        # matched un-split literals would re-open exactly the hole the gate just closed.
        pha_flatten "$pha_leaf"
        case "$PHA_FLAT" in *cc-permission-harvest*) ;; *) continue ;; esac
        pha_tool=0; pha_apply=0; pha_head=""; pha_dollar=0
        pha_words=()
        set -f
        IFS=$' \t\n' read -r -a pha_words <<<"$pha_leaf"
        set +f
        for pha_tok in "${pha_words[@]}"; do
          case "$pha_tok" in *'$'*) pha_dollar=1 ;; esac
          pha_flatten "$pha_tok"; pha_tok="$PHA_FLAT"
          if [ -z "$pha_head" ]; then
            case "$pha_tok" in *=*) ;; *) pha_head="${pha_tok##*/}" ;; esac
          fi
          case "${pha_tok##*/}" in cc-permission-harvest) pha_tool=1 ;; esac
          case "$pha_tok" in --apply|--apply=*) pha_apply=1 ;; esac
        done
        case "$pha_head" in echo|printf|cat|tee|true|:) continue ;; esac
        if [ "$pha_tool" = 1 ] && [ "$pha_apply" = 1 ]; then PHA_DENY=1; fi
        # Same rule as the tokenizer's: a `$` in a leaf that names the tool is unresolvable here,
        # and the presence gate already proved both literals are in this command.
        if [ "$pha_tool" = 1 ] && [ "$pha_dollar" = 1 ]; then PHA_DENY=1; fi
      done <<<"$PHA_LEAVES"
      ;;
  esac
  if [ "$PHA_DENY" = 1 ]; then
    deny "cc-permission-harvest --apply blocked — permission config is AUTHORIZATION, and an agent widening its own allowlist is the one thing this fleet's guardrails cannot police afterwards. The apply is the OPERATOR's, through the queue the weekly run already files: cc-do prints every rule, its evidence and the per-file diff, takes a typed 'yes', and only then writes. Run 'cc-do --list', find the row titled 'Apply the N harvested allow rules ...', and hand the operator its id. EVERYTHING ELSE ABOUT THIS TOOL IS YOURS: 'cc-permission-harvest 30' reports, '--json --out <dir>' writes a proposal, and '--check' previews EXACTLY what apply would write, rule by rule, read-only — if you wanted to know what would happen, that is the flag. This refusal reads your argv, not your text: an absolute path, an interpreter prefix, CONFIRM=1 or a bash -c wrapper change nothing, and there is no override variable. If you are only QUOTING the command, quote it as one string or leave --apply off that line."
  fi
fi
# ── PERMHARVEST-APPLY END ───────────────────────────────────────────────────────────────────────

# ── Warn (ask): destructive but sometimes intentional ────────────────

# git reset --hard — can destroy uncommitted work
if echo "$CMD" | grep -qE 'git[[:space:]]+reset[[:space:]]+--hard\b'; then
  warn "git reset --hard can destroy uncommitted work. Verify intentional."
fi

# git clean -x / -X removes gitignored files (may include paid assets).
# Match any flag bundle containing x or X after `git clean -`.
if echo "$CMD" | grep -qE 'git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*[xX]'; then
  warn "git clean -x/-X removes gitignored files which may include paid assets (AI-generated images, API outputs). Confirm intentional — safer alternative is git clean -fd (no -x)."
fi

# Recursive rm on non-safe targets. Per-target evaluation avoids the compound-command escape
# hatch (e.g., `rm -rf src && rm -rf node_modules` used to silently pass because one clause
# matched a safe target).
SAFE_RM_TARGETS='(node_modules|\.next|dist|__pycache__|\.cache|build|\.turbo|coverage|test-results|out|\.vercel|artifacts|\.pytest_cache|target|\.tox|htmlcov|\.ruff_cache|\.mypy_cache)'

# ── SCRATCHPAD-CATEGORY BEGIN ───────────────────────────────────────────────────────────────────
# The session's OWN harness scratchpad — a MISSING CATEGORY, not a widening of the list above.
#
# SAFE_RM_TARGETS allowlists build-artifact NAMES. It has no entry for
# `/private/tmp/claude-<uid>/<project>/<sessionUUID>/scratchpad`, the per-session temp tree the
# harness creates and instructs every agent to use for throwaways. So an agent that builds a
# throwaway there and removes it draws `rm -r on non-build-artifact target` → a PreToolUse
# confirmation modal → a PERMANENT stall for a DISPATCHED session, because cross-pane keystrokes
# are classifier-denied to agents and `cc-teardown` returns DEFER `tty-busy`: nothing but the
# operator can clear it. Measured 2026-08-18, four sessions lost in 24 h — panes 275/276, pane 339
# on a mutant binary it had built to prove a test RED, and pane 131, THE 24/7 DRAIN CHAIN itself,
# which dead-stopped ~4 h at recycle #21 with no alarm at all. Backlog 7da9c4451540.
#
# The decision is made on the RESOLVED path, never on a prefix a caller can spell. This file has
# already paid for the other approach: its `-rf` denylist let 11 of 13 equivalent spellings past
# AND denied its own fix commit (MEMORY.md denylist-enumerates-spellings-not-the-class). A spelling
# allowlist fails the same way, and here it fails in the DANGEROUS direction —
# `…/<sid>/scratchpad/../../../../Development/reso-management-app` is a prefix match and a repo
# delete. So: resolve the target (following a symlink chain on the final component too), resolve
# the root, require containment. `..`, a symlink into a repo, a crafted look-alike prefix and
# another session's scratchpad then all fail CLOSED by construction rather than by enumeration.
#
# Identity comes from the harness payload's own `.session_id` (`_P_SID`), never from the command:
# the UUID is the discriminator, so no session can name another's tree. The root SPELLING is shared
# with scripts/scratchpad-reaper.sh — the reaper that GCs this same tree — through the same
# CC_SCRATCHPAD_ROOT seam, so the two cannot drift on where the scratchpad is.
#
# Cost: nothing below runs unless a recursive rm has ALREADY failed the name allowlist, so this is
# off the modal path entirely (docs/research/validate-bash-fork-census-2026-08-17.md).
_SP_ROOT=""; _SP_ROOT_DONE=0
session_scratchpad_root() {  # → the RESOLVED root on stdout, or nothing at all
  if [[ "$_SP_ROOT_DONE" == 1 ]]; then printf '%s' "$_SP_ROOT"; return; fi
  _SP_ROOT_DONE=1
  local sid="$_P_SID" cand
  # A UUID, or nothing — `-` is the payload parse's own placeholder for absent. The shape check is
  # also what keeps the value out of the glob below: no `*`, no `/` and no `..` can survive it.
  [[ "$sid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || return
  for cand in "${CC_SCRATCHPAD_ROOT:-/private/tmp/claude-${UID:-$(id -u)}}"/*/"$sid"/scratchpad; do
    [[ -d "$cand" ]] || continue
    _SP_ROOT=$( cd "$cand" 2>/dev/null && pwd -P ) || _SP_ROOT=""
    break
  done
  printf '%s' "$_SP_ROOT"
}

_sp_resolve() {  # <path> → the fully resolved path on stdout, or nothing if it cannot be resolved
  local p="$1" d b link i=0
  # An unexpanded or glob token cannot be resolved, and GUESSING at one is exactly the spoofable
  # prefix match this block exists to avoid. Undecidable ⇒ not this category ⇒ the ask stands.
  case "$p" in ''|*'$'*|*'`'*|*'*'*|*'?'*|*'~'*) return ;; esac
  # Follow a symlink CHAIN on the final component. `rm -r` unlinks a symlink rather than following
  # it, so this is deliberately STRICTER than rm itself: a link out of the scratchpad is the exact
  # shape that must not be admitted to a permissive category, and the cost of the strictness is one
  # ask on a case that was already asking.
  while [[ -L "$p" && "$i" -lt 20 ]]; do
    link=$(readlink "$p" 2>/dev/null) || return
    case "$link" in
      /*) p="$link" ;;
      *)  p="$(dirname "$p")/$link" ;;
    esac
    i=$(( i + 1 ))
  done
  if [[ -d "$p" ]]; then ( cd "$p" 2>/dev/null && pwd -P ); return; fi
  # Not a directory. Walk up to the deepest EXISTING ancestor — `cd` + `pwd -P` there is what
  # resolves every `..` and every intermediate symlink — then re-attach the remainder. Resolving
  # only the immediate parent would refuse `<scratchpad>/build-1/obj` for the sole reason that
  # `build-1` had already been removed, and "the path is not there" is not a reason to hold a
  # session at a modal. A `..` BELOW the deepest existing ancestor is unresolvable by construction,
  # so it abstains rather than guessing — the fail-closed direction.
  local rest=""
  while :; do
    d=$(dirname "$p"); b=$(basename "$p")
    case "$b" in ''|.|..) return ;; esac
    rest="${b}${rest:+/$rest}"
    if [[ -d "$d" ]]; then
      d=$( cd "$d" 2>/dev/null && pwd -P ) || return
      [[ -n "$d" ]] || return
      printf '%s/%s' "${d%/}" "$rest"
      return
    fi
    [[ "$d" == "$p" || "$d" == "/" || "$d" == "." ]] && return
    p="$d"
  done
}

is_own_scratchpad_target() {  # <argv-token> → 0 iff it RESOLVES strictly under THIS session's scratchpad
  local t="$1" root res
  # Absolute only. A relative token is resolved against a cwd this hook does not authoritatively
  # know, and a wrong cwd would answer the question in the permissive direction. The harness hands
  # every agent an absolute scratchpad path, so the restriction costs the category nothing.
  case "$t" in /*) ;; *) return 1 ;; esac
  root=$(session_scratchpad_root); [[ -n "$root" ]] || return 1
  res=$(_sp_resolve "$t");         [[ -n "$res"  ]] || return 1
  # STRICTLY under: the root itself is the harness's to create and the reaper's to remove.
  case "$res" in "$root"/*) return 0 ;; *) return 1 ;; esac
}
# ── SCRATCHPAD-CATEGORY END ─────────────────────────────────────────────────────────────────────

# ── SAME-COMMAND VARIABLE RESOLUTION ────────────────────────────────────────────────────────────
# The scratchpad category above is right, and still misses most of what it was built for, because it
# can only see a target spelled as a LITERAL absolute path — `_sp_resolve` refuses any token holding
# a `$` (:1112, deliberately: guessing at an unexpanded token is the spoofable prefix match it
# exists to avoid). Agents do not write literals. They write:
#
#     D=/private/tmp/claude-501/<slug>/<sid>/scratchpad/probe && rm -rf "$D"
#
# MEASURED against the harness's own PermissionRequest archive (~/.claude/autonomy/permission-archive,
# 2,684 resolved prompts, 2026-07-31 →): 968 of the 1,297 non-curl prompts (75%) carry a recursive
# rm, and 717 of those targets are variables. 291 of them resolve into a claude-501 session
# scratchpad tree — the category this file ALREADY sanctions, asked about anyway because of the
# spelling. It is the largest single non-curl prompt source in the fleet, and for a DISPATCHED
# session an ask is terminal (the four losses recorded in the SCRATCHPAD-CATEGORY comment above).
#
# WHY THIS CANNOT WIDEN THE CATEGORY. Resolution runs BEFORE the predicates and changes neither of
# them: the expanded token must still be absolute and must still `_sp_resolve` STRICTLY under THIS
# session's scratchpad root, symlink chains followed. So the only way a wrong expansion can permit
# anything is by landing inside the session's own scratchpad — the safe case, by construction.
# A token that does not fully resolve keeps its `$` and is refused exactly as before.
#
# AND IT REFUSES AMBIGUITY RATHER THAN PICKING. A name assigned more than once, or assigned from a
# command substitution / a glob (`D=$(mktemp -d)`), has no decidable value at hook time, so it is not
# resolved at all. That is what stops `D=<scratchpad>; D=$(…); rm -rf "$D"` being read as its first
# assignment.
#
# ⚠️ 2026-09-09 — A CHAIN IS NOT AN AMBIGUITY (row 6293bf3bbbf1). Until today this refused any value
# holding a `$` AT ALL, which put a reference to an already-resolved literal in the same bucket as a
# command substitution. So the commonest agent spelling of the sanctioned category could never match:
#
#     S=/private/tmp/claude-501/<slug>/<sid>/scratchpad && CH=$S/probe && rm -rf "$CH"
#
# `CH` refused ⇒ the token keeps its `$` ⇒ `_sp_resolve` refuses it ⇒ an `ask`, which is TERMINAL for
# a dispatched session. Measured 2026-09-08: pane 314 frozen ~20 min, pane 616 three times in 25 min.
# A value may now carry PLAIN variable references (`$NAME` / `${NAME}`); `_rm_expand_token`'s existing
# 4-iteration bound is what resolves the chain, and a link that does not resolve simply leaves a `$`
# in the token, which is refused exactly as before. Everything genuinely undecidable is still refused,
# and the list is now explicit rather than a single `$` catch-all:
#   · command substitution `$(…)` or backticks, and globs `*` `?`   — no value at hook time
#   · arithmetic `$((…))`, `${A:-b}`, `$1`, `$@`                    — not a plain reference
#   · a SINGLE-QUOTED value carrying `$`                            — literal to the shell, so
#     resolving it would name a path the shell never would
# The safety argument above is unchanged and is what makes this narrow: resolution runs BEFORE the
# predicates and cannot widen them, so a wrong expansion can only ever permit something by landing
# STRICTLY inside this session's own scratchpad — the safe case, by construction.
_rm_literal_assignment() {  # <NAME> → its value iff assigned EXACTLY ONCE, DECIDABLY, in this command
  local name="$1" all one val probe
  all=$(printf '%s\n' "$CMD" \
        | grep -oE "(^|[[:space:];&|(])${name}=[^[:space:];&|]*" \
        | sed -E "s|^[[:space:];&|(]*${name}=||")
  [[ -n "$all" ]] || return 1
  [[ "$(printf '%s\n' "$all" | sort -u | wc -l | tr -d ' ')" == "1" ]] || return 1   # reassigned
  one=$(printf '%s\n' "$all" | head -1)
  # A single-quoted value is LITERAL to the shell: a `$` in it is not a reference.
  case "$one" in "'"*"'") case "$one" in *'$'*) return 1 ;; esac ;; esac
  val=$(printf '%s\n' "$one" | sed -E 's|^"||; s|"$||; s|^'"'"'||; s|'"'"'$||')
  # Two cases, not one: the command-substitution literal is spelled "\$(" rather than '$(' because
  # SC2016 reads a `$` inside single quotes as a mistake and reds the land — and a blanket disable
  # would suppress that warning on every pattern in the arm, not just this one. (A comment whose
  # FIRST word is the linter's own name parses as a directive, which is its own error: SC1072/SC1073.)
  case "$val" in *'`'*|*'*'*|*'?'*) return 1 ;; esac               # backtick / glob — undecidable
  case "$val" in *"\$("*) return 1 ;; esac                         # command substitution — likewise
  # Every surviving `$` must be a PLAIN reference. Delete the two decidable spellings and refuse if
  # anything is left — a denylist of the bad forms would enumerate spellings, not the class
  # (fleet memory: denylist-enumerates-spellings-not-the-class).
  probe=$(printf '%s' "$val" | sed -E 's/\$\{[A-Za-z_][A-Za-z0-9_]*\}//g; s/\$[A-Za-z_][A-Za-z0-9_]*//g')
  case "$probe" in *'$'*) return 1 ;; esac
  printf '%s\n' "$val"
}

_rm_expand_token() {  # <token> → the token with resolvable same-command variables expanded
  local t="$1" i name val braced plain
  for i in 1 2 3 4; do
    case "$t" in *'$'*) ;; *) break ;; esac
    # Greedy `.*` takes the LAST reference and the loop walks the rest. The captured name is
    # maximal, so driving from the REFERENCE rather than from the assignment list is what stops
    # `$D` from matching inside `$DIR`.
    name=$(printf '%s' "$t" | sed -nE 's/.*\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?.*/\1/p' | head -1)
    [[ -n "$name" ]] || break
    val=$(_rm_literal_assignment "$name") || break
    [[ -n "$val" ]] || break
    # Escaped-$ inside double quotes, so these are the LITERAL strings `${NAME}` and `$NAME` —
    # they are patterns to match in the token, never expansions to perform.
    braced="\${$name}"; plain="\$$name"
    t="${t//$braced/$val}"
    t="${t//$plain/$val}"
  done
  printf '%s' "$t"
}

# ── SELF-CREATED-TEMP CATEGORY ──────────────────────────────────────────────────────────────────
# `T=$(mktemp -d) … rm -rf "$T"` is the single largest source of manual permission prompts on this
# machine: 165 of the 721 `rm -r on non-build-artifact target` asks over the 30 days to 2026-09-10
# (replay of the 2,838 archived Bash prompts in ~/.claude/autonomy/permission-archive through THIS
# hook, so the count is what would prompt TODAY, not what prompted then).
#
# It is refused for a reason that is correct in general and wrong here. `_rm_literal_assignment`
# refuses any value carrying a command substitution, because `$(…)` has no decidable value at hook
# time — and a guess at a path is the spoofable prefix match the whole span exists to avoid.
#
# WHY THIS ONE IS DECIDABLE WITHOUT KNOWING THE PATH. We never learn where the directory is, and we
# do not need to: `mktemp -d` CREATES A NEW UNIQUE DIRECTORY, by contract. So a token resolving to
# it can only ever name something THIS COMMAND MADE, wherever mktemp chose to put it. Removing it
# cannot reach anything that existed before the command ran. That is a stronger guarantee than
# either predicate above, both of which reason from a LOCATION and are therefore vulnerable to a
# wrong expansion; this one reasons from PROVENANCE and is not.
#
# WHAT IS STILL REFUSED — each of these is a real lever a slip or an attacker would pull:
#   · the name assigned more than once — `T=$(mktemp -d); T=/etc; rm -rf "$T"` has no single value
#   · anything in the substitution but a lone `mktemp` — `$(mktemp -d; echo /etc)`, `$(x && mktemp -d)`
#   · `mktemp` WITHOUT a directory flag — that is a FILE, so an `rm -r` on it means the token was
#     built some other way; refusing costs one prompt on a shape nobody writes
#   · a token that is not the variable itself or a path strictly under it — `$T/..`, `$T/../../etc`
#   · a token whose `$` survives for any OTHER reason — unchanged, it never reaches this predicate
#
# NOT WIDENED, deliberately — the measured part a future session should not "finish". The
# neighbouring class is 152 asks whose target resolves to a LITERAL path under /tmp or /private/tmp.
# That looks like the same category and is not: those roots carry LIVE infrastructure this fleet
# depends on — `/tmp/cc-daemon-501/**` (daemon sockets), `/private/tmp/.desk-land-*` (land locks),
# `/tmp/cc-telemetry`. A blanket temp-root permit deletes those with no prompt, and an exclusion
# list for them would enumerate spellings rather than the class (MEMORY.md
# denylist-enumerates-spellings-not-the-class). The invariant that makes THIS category safe — the
# command created it — is the one to generalize, never the location.
_rm_is_mktemp_dir_substitution() {  # <assignment-value> → 0 iff it is exactly `$(mktemp -d …)`
  local v="$1" inner a
  # Strip one layer of surrounding quotes, then require the WHOLE value to be one substitution.
  v=$(printf '%s' "$v" | sed -E 's|^"||; s|"$||')
  case "$v" in
    '$('*')') inner=${v#'$('}; inner=${inner%')'} ;;
    *) return 1 ;;
  esac
  # Nothing may precede or follow the mktemp call INSIDE the substitution: a separator would let a
  # second command choose the value. `$(mktemp -d)` yes; `$(mktemp -d; echo /etc)` no.
  case "$inner" in *';'*|*'&'*|*'|'*|*'`'*|*'$('*|*$'\n'*) return 1 ;; esac
  # First word must be mktemp itself (an absolute path to it is fine), and a directory flag must be
  # a real argv token — `-d`, `--directory`, or a cluster carrying d such as `-dt`.
  # shellcheck disable=SC2086  # deliberate word-split: $inner is the substitution's argv
  set -- $inner
  [ $# -ge 1 ] || return 1
  case "$1" in mktemp|*/mktemp) ;; *) return 1 ;; esac
  shift
  for a in "$@"; do
    case "$a" in
      --directory) return 0 ;;
      --*) ;;
      -*) case "$a" in *d*) return 0 ;; esac ;;
    esac
  done
  return 1
}

is_self_created_mktemp_target() {  # <argv-token> → 0 iff it names a dir THIS command's mktemp made
  local t="$1" name rest all one
  # The token must be the variable, optionally with a path strictly UNDER it. Any `..` is refused
  # outright: a suffix that walks up leaves the directory mktemp created, which is the whole basis.
  case "$t" in *'..'*|*'*'*|*'?'*|*'`'*) return 1 ;; esac
  name=$(printf '%s' "$t" | sed -nE 's|^\$\{([A-Za-z_][A-Za-z0-9_]*)\}(/.*)?$|\1|p; s|^\$([A-Za-z_][A-Za-z0-9_]*)(/.*)?$|\1|p' | head -1)
  [ -n "$name" ] || return 1
  # Whatever follows the variable must be a plain path segment chain — no second reference.
  rest=$(printf '%s' "$t" | sed -E "s|^\\\$\{?${name}\}?||")
  case "$rest" in ''|/*) ;; *) return 1 ;; esac
  case "$rest" in *'$'*) return 1 ;; esac
  # Exactly one assignment of that name in this command — the same uniqueness rule the literal-path
  # resolver uses, for the same reason: a reassigned name has no decidable value.
  #
  # The extraction is SUBSTITUTION-AWARE, and it has to be. `_rm_literal_assignment`'s pattern ends
  # the value at the first whitespace (`[^[:space:];&|]*`), which is right for a literal path and
  # silently truncates `T=$(mktemp -d)` to `T=$(mktemp` — a value that then matches no arm here and
  # permits nothing. That truncation is invisible: the predicate simply returns 1 and the ask stands,
  # which looks exactly like the category working. So the two alternatives below are ordered
  # substitution-first, and only a value with NO `$(` falls through to the whitespace-terminated form.
  all=$(printf '%s\n' "$CMD" \
        | grep -oE "(^|[[:space:];&|(])${name}=(\"?\\\$\([^()]*\)\"?|[^[:space:];&|]*)" \
        | sed -E "s|^[[:space:];&|(]*${name}=||")
  [ -n "$all" ] || return 1
  [ "$(printf '%s\n' "$all" | sort -u | wc -l | tr -d ' ')" = "1" ] || return 1
  one=$(printf '%s\n' "$all" | head -1)
  _rm_is_mktemp_dir_substitution "$one"
}
# ── SELF-CREATED-TEMP END ───────────────────────────────────────────────────────────────────────

# rm_target_is_permitted <argv-token> — the THREE predicates. The third is checked on the RAW token,
# not the resolved one: its whole point is a value that CANNOT be resolved (a command substitution),
# so resolution has already refused it by the time we get here.
rm_target_is_permitted() {
  local resolved
  resolved=$(_rm_expand_token "$1")
  is_safe_rm_target "$resolved" || is_own_scratchpad_target "$resolved" \
    || is_self_created_mktemp_target "$1"
}

# is_safe_rm_target <argv-token> — shared by both paths below, for the same no-drift reason.
is_safe_rm_target() {
  # Strip leading `./` or `/` (but NOT a leading `.` — `.next` must match `\.next`).
  # Two separate subs to avoid `|` collision with sed's delimiter.
  local stripped
  stripped=$(printf '%s' "$1" | sed -E 's|^\./||; s|^/||')
  printf '%s' "$stripped" | grep -qE "^${SAFE_RM_TARGETS}(/|$)"
}

if [[ "$RM_PRESENT" == "1" && "$RM_SCAN_OK" == "1" ]]; then
  # Same spelling blindness as the deny above lived here too, one flag-bundle enumeration further
  # on: `-(r|rf|fr)` knew neither `-R` nor `--recursive`, so `rm -Rf /etc` and
  # `rm --recursive --force src` emitted no decision at all. Recursive in ANY spelling, with or
  # without force, is the trigger — unchanged in meaning, only in reach.
  while IFS=$'\t' read -r rm_rec rm_force rm_target; do
    [[ "$rm_rec" == "1" ]] || continue
    if ! rm_target_is_permitted "$rm_target"; then
      warn "rm -r on non-build-artifact target: '$rm_target'. Verify intentional."
    fi
  done <<<"$RM_SCAN"
elif [[ "$RM_PRESENT" == "1" ]]; then
  RM_OCCURRENCES=$(echo "$CMD" | grep -oE 'rm[[:space:]]+(-[a-zA-Z-]+[[:space:]]+)*[^[:space:];&|-][^[:space:];&|]*' || true)
  if [[ -n "$RM_OCCURRENCES" ]]; then
    while IFS= read -r occurrence; do
      printf '%s' "$occurrence" | grep -qE '(^|[[:space:]])-[a-zA-Z]*[rR][a-zA-Z]*([[:space:]]|$)|--recursive([[:space:]=]|$)' || continue
      target=$(printf '%s' "$occurrence" | sed -E 's/^rm[[:space:]]+(-[a-zA-Z-]+[[:space:]]+)*//')
      if ! rm_target_is_permitted "$target"; then
        warn "rm -r on non-build-artifact target: '$target'. Verify intentional."
        # shellcheck disable=SC2317  # reachable: warn() exits, so this only runs if warn is stubbed
        break
      fi
    done <<<"$RM_OCCURRENCES"
  fi
fi

# (Layer-3 #9 writer-lock guard removed 2026-06-03 — always-worktree isolation makes it a
# no-op; the reso-writer-lock.py + concurrent-writer-guard.sh stack was deleted. See the
# parallel-sessions-simple plan / memory parallel-sessions-simple-2026-06-03.)

# Log command for audit — ISO timestamp + session id prefix (D-3). The bare `echo "$CMD"` left a
# 13 MB log with no attribution and no line anchor: nothing was greppable by session, and a
# multi-line command shredded the line structure with no way to tell a continuation line from a
# new entry. `.session_id` comes from stdin (never CLAUDE_SESSION_ID — CC does not export it, D-9).
#
# ZERO forks on the modal path (fork census 2026-08-17,
# docs/research/validate-bash-fork-census-2026-08-17.md §6 levers 2-3). These four lines used to
# exec jq + mkdir + date on EVERY invocation — 7.2 ms, 10% of the modal path's 71.9 ms, to append
# one audit line. Both fields now come from the single payload parse at the top of the file:
# `todateiso8601` there is byte-identical to `date -u '+%Y-%m-%dT%H:%M:%SZ'` (verified), and bash
# 3.2.57 here has no `printf '%(...)T'`, so jq is the only fork-free source of the stamp.
# Nothing above this point is touched: every deny/ask decision is already made, so a fault here
# can lose an audit line but can never open the gate.
SID="$_P_SID"
TS="$_P_TS"
# `date` is forked ONLY if the single parse somehow yielded no stamp — never on the modal path.
[ -n "$TS" ] || TS=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
# `[ -d ]` is a builtin; the directory exists on every call after the first, so the fork was pure loss.
[ -d ~/.claude/logs ] || mkdir -p ~/.claude/logs
echo "[$TS] [$SID] $CMD" >> ~/.claude/logs/bash-commands.log
exit 0
