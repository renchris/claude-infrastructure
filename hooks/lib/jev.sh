#!/usr/bin/env bash
# jev.sh — the ONE way a hook asks Jev a typed question. Source it; do not re-implement it.
#
# WHY A LIBRARY AND NOT A CALL SITE. Two hooks want this (anti-deference-nudge and
# completion-assert's authorship arm) and the repo has a standing lesson about exactly that
# shape: `sibling-auditors-must-share-the-state-model` — two checks over one population
# disagreed because only one of them modelled a state. One spelling of "ask Jev", or the two
# hooks drift apart on thresholds, on redaction, and on what a timeout means.
#
# ── THE SAFETY INVARIANT, and every consumer inherits it ─────────────────────────────────────
# Jev may only ever move a decision in the direction today's regex is MEASURED to get wrong,
# and only above CC_JEV_MIN_P. It may never:
#   · suppress a fire the existing matcher already produces,
#   · weaken a deny, a carve-out, or a safety gate,
#   · change behaviour at all when it cannot answer.
# ANY abstain — no key, no deps, timeout, HTTP, kill switch — leaves the caller on exactly
# today's code path. That is what makes landing this a no-op until someone deliberately turns
# it on, and it is why `jev_ask` returns non-zero rather than a default answer.
#
# ── WHY 0.90 — MEASURED ON THIS TASK, after 0.98 shipped INERT ───────────────────────────────
# 🚨 0.98 was imported from a DIFFERENT task's calibration and was unreachable here. Measured
# 2026-09-19 on 20 synthetic closes written for the probe (tests/fixtures/jev-synthetic-closes.json,
# scripts/jev/synthetic-probe.sh — no private data, so it runs without the ZDR question):
#
#   true deferrals   p in [0.81, 0.95], mean 0.93   <- NEVER reaches 0.98
#   finished work    p in [0.05, 0.08], mean 0.06
#   genuine blockers p in [0.20, 0.93]
#
# At 0.98 the arm fires 0/10 on true deferrals: a landed feature that cannot fire is inert, which
# is the failure this repo keeps re-learning. At 0.90 it fires 3/10 with 0/6 and 0/4 FALSE fires.
# The threshold is barely the binding constraint — blocker_class is (it answers `none` on 4 of 10
# true deferrals) — so anything <= 0.93 yields the same 3/10, and 0.90 is chosen to sit below the
# lowest drivable-classed deferral (0.93) without reaching for recall the class gate will not give.
#
# 🚨 THE LIMIT, STATED SO IT CANNOT BE READ AS CALIBRATION: n=20, SYNTHETIC, authored by the agent
# whose prose the arm judges. It proves the shipped constant was unreachable and that specificity
# is intact; it does NOT establish recall on real closes. `cc-jev pilot` against the 85 real labels
# remains the only thing that can, and it should RE-DERIVE this number rather than inherit it.
#
# ── WHY A HIGH THRESHOLD AT ALL ──────────────────────────────────────────────────────────────
# Not a taste call. On the one independent benchmark (docs/research/jev-at-cost-api-2026-09-18.md
# §2) Jev's aggregate accuracy LOSES to Haiku 4.5 (62.6% vs 81.3%) and its aggregate ECE loses
# too — but it emits 101 distinct probability values against Haiku's 10, and in its top bin
# (p>=0.98) it decides 7.0% of cases at 97.8% accuracy. The usable product is that
# high-precision tail, not the verdict. So: act only in the tail, abstain everywhere else, and
# never read a mid-band probability as a weak yes. A p of 0.5 is maximum UNCERTAINTY, not "no" —
# the SDK's own type says so: "Model-estimated P(true). Not confidence in either outcome."
#
# ── WHAT MUST NEVER BE SENT ──────────────────────────────────────────────────────────────────
# Callers pass a BOUNDED, PURPOSE-BUILT excerpt — the message under judgment — never a
# transcript, a mailbox, or the `msg` corpus. ZDR is on and fails closed, which is what makes
# model-authored prose acceptable; it is not a licence to widen the payload. jev_ask enforces
# the size ceiling mechanically (CC_JEV_MAX_STATE_B) because a rule stated only in prose is a
# rule nothing executes.
#
# Kill switch: CC_JEV=0 (and absence of AI_GATEWAY_API_KEY is itself an off switch).

# ── ROOT RESOLUTION MUST FOLLOW THE SYMLINK, AND THIS IS NOT A DETAIL ───────────────────────
# The live layer (~/.claude) is a per-file symlink farm over this checkout. A hook sourcing this
# file does so as ~/.claude/hooks/lib/jev.sh, so a naive dirname/../.. yields ~/.claude — which
# has no node_modules and never will, because node_modules is gitignored and lives in the
# CHECKOUT. Unresolved, `jev_available` would return false forever in exactly the environment
# this code exists to run in, and it would do so SILENTLY, since unavailable is a legitimate
# state. That is memory `symlinked-$0-splits-siblings` verbatim: one invocation splits into a
# half that resolves and a half that dies.
# Resolved with a portable loop rather than `readlink -f` (GNU-only semantics on older Darwin).
_jev_resolve_root() {
  local src="${BASH_SOURCE[0]}" dir
  while [ -L "$src" ]; do
    dir="$(cd -P "$(dirname "$src")" && pwd)"
    src="$(readlink "$src")"
    case "$src" in /*) ;; *) src="$dir/$src" ;; esac
  done
  (cd -P "$(dirname "$src")/../.." && pwd)
}
CC_JEV_LIB_ROOT="${CC_JEV_LIB_ROOT:-$(_jev_resolve_root)}"
: "${CC_JEV_MIN_P:=0.90}"
# 2500: measured steady state on the agent-secrets + proxy path is 742-791 ms, and a cold
# proxy took 1515 ms. See scripts/jev/evaluate.mjs for why 1500 was not the 2x it looked like.
: "${CC_JEV_TIMEOUT_MS:=2500}"
: "${CC_JEV_MAX_STATE_B:=24000}"   # well under Jev's 32k-TOKEN state ceiling; bytes are the cheap bound

# ── WHERE THE KEY COMES FROM: INJECTED, NEVER EXPORTED ───────────────────────────────────────
# This machine runs `agent-secrets` (sops + age, names-only). Its golden rule 3 is "to use a
# secret, inject it — don't read it", and an `export AI_GATEWAY_API_KEY=…` in a shell profile is
# precisely the plaintext-on-disk leak that tool exists to prevent. So there are two paths, in
# this order:
#   1. the variable is ALREADY in our environment  → use it, fork nothing extra (the fast path,
#      and what a session launched through ~/bin/claude-agent gets for free);
#   2. otherwise, if an agent-secrets store exists → run evaluate.mjs under
#      `agent-secrets run --`, which decrypts into the CHILD's environment for that run only and
#      dies with it. Measured cost of the wrapper on this box: ~230 ms.
# If neither holds, jev_available is false and every consumer falls through to today's behaviour.
#
# 🚨 EGRESS. `agent-secrets run` starts a loopback CONNECT proxy whenever
# ~/.config/secrets/egress.allow exists, and sets the child's HTTPS_PROXY. A host missing from
# that file is BLOCKED — which would surface here as a bare `http` abstain and look like a
# network blip forever. `cc-jev status` checks the file by name and says so outright rather than
# leaving it to be rediscovered. Adding a host to it is an AUTHORISATION change and is the
# operator's alone; nothing here writes it.
CC_JEV_EGRESS_ALLOW="${CC_JEV_EGRESS_ALLOW:-$HOME/.config/secrets/egress.allow}"
CC_JEV_GATEWAY_HOST="${CC_JEV_GATEWAY_HOST:-ai-gateway.vercel.sh}"

# jev_secret_source — env | agent-secrets | none. Computed once per process; a hook is one process.
jev_secret_source() {
  if [ -n "${_JEV_SRC:-}" ]; then printf '%s' "$_JEV_SRC"; return 0; fi
  # Quoted literals: bare `_JEV_SRC=env` reads as a command substitution to shellcheck (SC2209),
  # and `env` really is a binary on PATH — the one spelling where that warning is not pedantry.
  if [ -n "${AI_GATEWAY_API_KEY:-}" ]; then _JEV_SRC='env'
  elif command -v agent-secrets >/dev/null 2>&1 \
       && agent-secrets list 2>/dev/null | grep -q 'AI_GATEWAY_API_KEY'; then _JEV_SRC='agent-secrets'
  else _JEV_SRC='none'; fi
  printf '%s' "$_JEV_SRC"
}

# jev_available — cheap. Answers "would a call have any chance of succeeding".
jev_available() {
  [ "${CC_JEV:-1}" != "0" ] || return 1
  [ "$(jev_secret_source)" != "none" ] || return 1
  [ -f "$CC_JEV_LIB_ROOT/scripts/jev/evaluate.mjs" ] || return 1
  [ -d "$CC_JEV_LIB_ROOT/node_modules/ai" ] || return 1
  command -v node >/dev/null 2>&1 || return 1
  return 0
}

# jev_ask <<< '{"state":…,"questions":{…}}'
#   stdout: ALWAYS one JSON object — {ok:true,answers,…} or {ok:false,reason}
#   rc 0  answered · rc 1 abstained (caller MUST fall through to its existing path)
#
# 🚨 THE REASON IS ON STDOUT, NOT IN A GLOBAL — and that is a bug fix, not a style choice.
# The obvious call shape is `printf '%s' "$spec" | jev_ask`, and the right-hand side of a pipe
# runs in a SUBSHELL, so any variable this function set would be discarded the instant it
# returned. The repo already carries that lesson twice over
# (`assignment-inside-command-substitution-never-escapes`, `subshell eats the global`) and the
# first draft of this file shipped the bug anyway — caught by tests 12 and 13 below. One
# channel, always JSON, works identically piped, here-stringed, or captured.
jev_ask() {
  local spec out rc
  spec="$(cat)"
  if ! jev_available; then printf '{"ok":false,"reason":"unavailable"}'; return 1; fi
  if [ "${#spec}" -gt "$CC_JEV_MAX_STATE_B" ]; then printf '{"ok":false,"reason":"oversize"}'; return 1; fi
  # No `2>/dev/null` on the node call's stdout path: a suppressed stderr turns a failed command
  # into a clean zero (`suppressed-stderr-turns-a-failed-command-into-a-zero`). stderr goes to
  # the hook's own stderr, where the harness records it; only stdout is consumed.
  if [ "$(jev_secret_source)" = "agent-secrets" ]; then
    # `run --` decrypts into THIS child only. The value never lands in our environment, in a
    # file, or in a transcript — which is the whole point of routing through the store.
    out="$(printf '%s' "$spec" | CC_JEV_TIMEOUT_MS="$CC_JEV_TIMEOUT_MS" \
          agent-secrets run -- node "$CC_JEV_LIB_ROOT/scripts/jev/evaluate.mjs")"
  else
    out="$(printf '%s' "$spec" | CC_JEV_TIMEOUT_MS="$CC_JEV_TIMEOUT_MS" \
          node "$CC_JEV_LIB_ROOT/scripts/jev/evaluate.mjs")"
  fi
  rc=$?
  # An empty capture is NOT "it printed nothing" — it is a killed or crashed child, and a
  # consumer that jq's it would read `null` and could mistake that for a verdict
  # (`killed-pipeline-empty-output-is-not-a-verdict`). Synthesise the abstain rather than
  # letting a blank reach the caller.
  if [ -z "$out" ]; then printf '{"ok":false,"reason":"no-output"}'; return 1; fi
  printf '%s' "$out"
  [ "$rc" -eq 0 ]
}

# jev_reason <result-json> — the abstain class, for logging. Always safe to call.
jev_reason() { printf '%s' "$1" | jq -r '.reason // "none"' 2>/dev/null || printf 'none'; }

# jev_bool_confident <result-json> <question-id> [min-p]
#   rc 0  → P(true) >= min-p            "confidently TRUE"
#   rc 1  → anything else, INCLUDING a confident false and a missing answer.
# There is deliberately no "confidently false" helper: no consumer needs one yet, and a second
# threshold nobody has calibrated is a number waiting to be quoted as if it were measured.
jev_bool_confident() {
  local json="$1" id="$2" minp="${3:-$CC_JEV_MIN_P}" p
  p="$(printf '%s' "$json" | jq -r --arg id "$id" '.answers[$id].probability // empty' 2>/dev/null)"
  [ -n "$p" ] || return 1
  awk -v p="$p" -v t="$minp" 'BEGIN{exit !(p+0 >= t+0)}'
}

# jev_window_open — REFUSE to spend money the operator never authorised.
#   rc 0 → the free Gateway window is open (or an explicit override is set); callers may proceed.
#   rc 1 → the window has lapsed; a loud refusal naming the override has been printed to stderr.
#
# 🚨 THIS GUARD DID NOT EXIST UNTIL 2026-09-21, AND ITS ABSENCE WAS A LIVE HAZARD. The free window
# ends 2026-09-25, and on that date `typesafe-ai/jev` does not stop answering — it becomes METERED
# at $0.042/MTok input. So every batch consumer written this week would have gone on calling, on
# the operator's card, with nothing in the code path aware that anything had changed. Until now
# `CC_JEV_FREE_UNTIL` was read at exactly ONE line in the whole tree (`bin/cc-jev`, inside a
# printf), i.e. it was a thing we DISPLAYED and never a thing we ENFORCED — the same shape as a
# limit that lives in a comment.
#
# It fails CLOSED on an unreadable clock: a date command that cannot answer leaves the window shut
# rather than open, because the failure it is guarding is spending, and the cost of a wrong refusal
# is a re-run while the cost of a wrong approval is a bill.
#
# `CC_JEV_PAID=1` is the deliberate override, and it is deliberately an ENV VAR rather than a flag:
# authorising spend is the operator's act, and it should have to be typed.
jev_window_open() {
  local until="${CC_JEV_FREE_UNTIL:-2026-09-25}" today
  [ "${CC_JEV_PAID:-0}" = 1 ] && return 0
  today="$(date -u +%Y-%m-%d 2>/dev/null)"
  if [ -z "$today" ]; then
    printf '✗ REFUSING: cannot read the clock, so the free-window check cannot be made.\n' >&2
    printf '  Failing closed — past %s these calls are billed. Override: CC_JEV_PAID=1\n' "$until" >&2
    return 1
  fi
  # String comparison is correct and intentional for ISO-8601 dates: they sort lexically.
  if [ "$today" \> "$until" ]; then
    printf '✗ REFUSING: the free AI Gateway window closed on %s (today is %s).\n' "$until" "$today" >&2
    printf '  Calls past it are BILLED at 0.042 USD per MTok input — they do not fail, they charge.\n' >&2
    printf '  If that is intended, authorise it explicitly:  CC_JEV_PAID=1 <command>\n' >&2
    return 1
  fi
  return 0
}

# jev_is_mock — rc 0 when the configured route is a LOCAL TEST DOUBLE, not the vendor.
#
# 🚨 IT EXISTS SO THAT MOCK-PRODUCED ROWS CANNOT BE READ AS REAL VERDICTS. Every consumer in this
# subsystem discovers its input by globbing ~/.claude/autonomy for jev-*.jsonl, and a hand repro
# run against the local mock writes there exactly like a real run does — same filename shape, same
# row schema, same timestamp ordering. Measured 2026-09-21: six such files accumulated in a single
# afternoon, one of them newer than the real 140-row run, and two separate consumers read them.
# The anchor picker chose a 5-row mock whose every row named a fixture absent from disk and then
# refused with "no weak-incumbent anchors" — true about the file it picked, false about the machine.
# `cc-jev status` reported "8 verdict(s)" over a mock pass.
#
# Sorting them out by eye works once and does not scale: the discriminator was "do these filenames
# look like alpha.md" — a judgment, applied by hand, to a store that grows. So the ROW says what it
# is, at the moment it is written, from the one fact that settles it: the URL the call went to.
# A file that predates this marker is UNMARKED, never assumed real — consumers treat "no marker"
# as unknown provenance and say so rather than guessing.
jev_is_mock() {
  case "${CC_JEV_BASE_URL:-}" in
    *127.0.0.1*|*localhost*|*'[::1]'*|*0.0.0.0*) return 0 ;;
    *) return 1 ;;
  esac
}
