#!/usr/bin/env bash
# cloud-ceiling-probe.sh — WHERE DOES THE CLOUD FLEET ACTUALLY BREAK?
#
#   scripts/cloud-ceiling-probe.sh --control            classify a KNOWN refusal (free, spends nothing)
#   scripts/cloud-ceiling-probe.sh --account <a> --max N [--confirm]   ramp creates until refusal
#   scripts/cloud-ceiling-probe.sh --report             re-print the last run's ledger
#
# ── THE QUESTION, AND WHY IT IS NOT THE OBVIOUS ONE ──────────────────────────────────────────────
# Moving sessions off-box relieves CPU and RAM. It does NOT relieve TOKENS. So the fleet ceiling
# does not disappear when the box stops being the constraint — it MOVES, from 64 GB of RAM to
# per-account rate limits, and nobody has measured where it lands. CONCURRENCY_PROGRAM.md §S5 rests
# on that number.
#
# "~15 concurrent sessions" is folklore precisely because it was never measured this way, so the
# one thing this script must not do is produce another number of the same kind. Hence §7's
# discipline (CLOUD_OBSERVABILITY.md): a measurement is published WITH the command that produced it,
# so a reader re-runs it instead of believing it.
#
# ── THREE OUTCOMES, NEVER TWO ────────────────────────────────────────────────────────────────────
# A create either succeeds, is refused for QUOTA, or is refused for SOMETHING ELSE. Folding the
# third into the second is how a network blip becomes a published ceiling:
#
#   created        stdout carries `session_…`                      → the ramp continues
#   refused-quota  the refusal names a limit/quota/rate condition   → THE CEILING. Stop, report N.
#   refused-other  refused, and the reason is not a limit           → A NON-VERDICT. Stop, report
#                                                                     UNKNOWN, publish NO number.
#
# The third arm is the whole reason this is a script and not a for-loop. A ramp that treats every
# non-success as "we hit the wall" reports a ceiling of N for a wall that was a DNS failure.
#
# ── THE POSITIVE CONTROL IS FREE, SO THERE IS NO EXCUSE FOR NOT RUNNING IT ───────────────────────
# The classifier above is the instrument, and an unvalidated classifier is how a wrong ceiling gets
# published with confidence. It needs a create that is KNOWN to be refused for quota — and the
# fleet supplies one for nothing: an account already at 100% weekly. `--control` fires exactly one
# create against such an account and asserts the classifier returns `refused-quota`.
#
# If the control returns `created`, the account was not actually limited and the control is void.
# If it returns `refused-other`, THE CLASSIFIER IS WRONG — its patterns do not match this API's real
# refusal string — and any ramp run before fixing that would silently publish a `refused-other` wall
# as a non-verdict, or worse, miss the real one. Either way: fix the classifier, do not ramp.
# (Measured 2026-08-08: next2 sat at 100% weekly, resetting ~1.7h later. Re-pick from the live
# `claude-accounts` readout at run time — an account at 100% is a PERISHABLE fact and a hardcoded
# one would silently stop being a control.)
#
# ── COST, STATED PLAINLY ─────────────────────────────────────────────────────────────────────────
# EVERY create spends real weekly quota on a real account. That is why `--confirm` is required, why
# `--max` has no default, and why the ramp stops at the FIRST refusal rather than confirming it.
# A stop for any reason other than a refusal is reported as a LOWER BOUND ("at least N"), never as
# the ceiling — an early stop bounds the measurement, it does not complete it.
set -euo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
LEDGER="${CLOUD_CEILING_LEDGER:-$HOME/.claude/autonomy/cloud/ceiling-probe.jsonl}"
ACCOUNTS_JSON="${CLOUD_CEILING_ACCOUNTS:-$HOME/.claude/accounts.json}"
# ── RESOLVING THE BINARY, WHICH IS WHERE THIS SCRIPT WOULD HAVE SILENTLY MEASURED NOTHING ────────
# `--cloud` exists on 2.1.220 and DOES NOT EXIST on the pinned 2.1.114. The obvious resolution —
# `command -v claude-latest` — was the first thing written here and it is WRONG: measured
# 2026-08-08 it announces *"2.1.226 available but not in MANIFEST allow-list. Staying on 2.1.114."*
# So every create would have been fired at a binary with no such flag, failed on an unrecognised
# argument, classified `refused-other`, and produced a permanent non-verdict — a probe that can
# never measure its own subject, failing in the one direction that looks like a finding.
#
# So resolve the RUNNING process, not a launcher name (memory:
# version-identity-is-the-running-process-not-the-launcher — a launcher's `--version` reports which
# binary the NAME points at, never which one is executing).
if [ -n "${CLOUD_CEILING_CLAUDE_BIN+set}" ]; then CLAUDE_BIN="$CLOUD_CEILING_CLAUDE_BIN"
else
  CLAUDE_BIN="${CLAUDE_CODE_EXECPATH:-}"
  [ -n "$CLAUDE_BIN" ] || CLAUDE_BIN="$(ps -o command= -p "${PPID:-0}" 2>/dev/null | awk '{print $1}')"
  case "$CLAUDE_BIN" in *claude*) ;; *) CLAUDE_BIN="" ;; esac
fi

# …and CHECK it, because resolving a binary is not the same as resolving a CAPABLE one. `--help`
# cannot answer this: `--cloud` is present-but-HIDDEN, and §6.1 records a retracted measurement that
# made exactly that mistake. A `strings` grep can, and it carries its own positive control —
# `ultrareview` is present in every build, so a control of 0 means the grep is reading nothing at
# all (a bad path) rather than the subject being absent. Measured 2026-08-08:
#     2.1.220  --cloud=21  ultrareview=134     ← capable
#     2.1.114  --cloud=0   ultrareview=71      ← flag genuinely absent, instrument demonstrably fine
cloud_flag_supported() { # 0 = yes · 1 = no · 2 = cannot tell (control failed) — three states
  local b="$1" real hits ctl
  [ -n "$b" ] && [ -x "$b" ] || return 2
  real="$(python3 -c "import os,sys;print(os.path.realpath(sys.argv[1]))" "$b" 2>/dev/null || printf '%s' "$b")"
  hits="$(strings -a "$real" 2>/dev/null | grep -c -- '--cloud' || true)"
  ctl="$(strings -a "$real" 2>/dev/null | grep -ci 'ultrareview' || true)"
  [ "${ctl:-0}" -gt 0 ] 2>/dev/null || return 2      # control dead ⇒ the grep proves nothing
  [ "${hits:-0}" -gt 0 ] 2>/dev/null || return 1
  return 0
}

ACCOUNT=""; MAXN=""; MODE=""; CONFIRM=0
while [ $# -gt 0 ]; do
  case "$1" in
    --account) ACCOUNT="${2:-}"; shift 2 ;;
    --max)     MAXN="${2:-}"; shift 2 ;;
    --confirm) CONFIRM=1; shift ;;
    --control) MODE=control; shift ;;
    --report)  MODE=report; shift ;;
    -h|--help) sed -n '2,50p' "$SELF" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "cloud-ceiling-probe: unknown arg $1" >&2; exit 2 ;;
  esac
done

# Refuse UP FRONT on an incapable binary. Not inside fire_one: there the refusal would arrive as
# one `refused-other` per attempt and read like a wall the ramp discovered, which is precisely the
# false finding this guard exists to prevent.
assert_capable() {
  local rc=0; cloud_flag_supported "$CLAUDE_BIN" || rc=$?
  case "$rc" in
    0) : ;;
    1) echo "REFUSING: '$CLAUDE_BIN' has no --cloud flag (2.1.114 does not; 2.1.220 does)." >&2
       echo "  Every create would fail on an unknown argument and be recorded as a non-verdict." >&2
       echo "  Run this from a session on a --cloud-capable binary, or set CLOUD_CEILING_CLAUDE_BIN." >&2
       exit 6 ;;
    *) echo "REFUSING: cannot tell whether '$CLAUDE_BIN' supports --cloud — the capability probe's" >&2
       echo "  own positive control came back empty, so it is reading nothing and proves nothing." >&2
       exit 6 ;;
  esac
}

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
# ── EVERY ROW CARRIES ITS RUN AND ITS CWD, OR THE LEDGER CANNOT BE READ ─────────────────────────
# The ledger is ONE shared file under ~/.claude and this box runs many sessions at once. Measured
# 2026-08-08 mid-measurement: rows from a concurrent probe interleaved with this run's, and because
# a row named only a timestamp and an account, no reader could tell which run produced which
# attempt — including `--report`, which just tails the last 40 lines.
# That is worse than lost provenance. A ceiling IS a count of rows, so two interleaved 2-create runs
# are indistinguishable from one 4-create run: the ledger can silently publish a doubled ceiling.
# `cwd` rides along because it turned out to be a live variable rather than context — creates from a
# git worktree hit `Bundle upload failed` where the same account from the main checkout succeeded
# back-to-back (CONCURRENCY_PROGRAM.md §S5.2), and no row recorded which was which.
RUN_ID="${CLOUD_CEILING_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
record() {
  mkdir -p "$(dirname "$LEDGER")"
  printf '%s\n' "$1" | jq -c --arg r "$RUN_ID" --arg c "$PWD" '. + {run:$r, cwd:$c}' >> "$LEDGER"
}

# config dir for an account name, from accounts.json — never a hardcoded path (a hardcoded one
# stops being true the moment an account is added or moved). The stored value carries a literal
# `~`, which is NOT expanded by the shell inside a variable, so it is expanded here; skipping that
# yields a path that exists nowhere and a create that fails for a reason having nothing to do with
# the ceiling being measured.
config_dir_for() {
  local a="$1" d
  [ -f "$ACCOUNTS_JSON" ] || { echo "" ; return 1; }
  d="$(jq -r --arg a "$a" '.accounts[]? | select(.name==$a) | (.config_dir // .configDir // empty)' \
       "$ACCOUNTS_JSON" 2>/dev/null | head -1)"
  # shellcheck disable=SC2088  # the quoted ~ is the literal we are MATCHING, not one to expand
  case "$d" in "~/"*) printf '%s/%s' "$HOME" "${d#\~/}" ;; *) printf '%s' "$d" ;; esac
}

# Quota comes from `claude-accounts --json`, whose rows live under `.rows[]` and key the account as
# `.acct` — NOT `.accounts[].name`, which is accounts.json's shape. Two different files, two
# different spellings for the same thing; assuming one shape for both returns empty for every
# account and every reading silently becomes "?".
weekly_pct_for() { # → integer, or "?" when unreadable. NEVER 0 on failure: 0 reads as "plenty left".
  local a="$1" v
  v="$(claude-accounts --json 2>/dev/null \
       | jq -r --arg a "$a" '.rows[]? | select(.acct==$a) | (.weekly_pct // empty)' 2>/dev/null | head -1)"
  case "$v" in ''|*[!0-9.]*) printf '?' ;; *) printf '%.0f' "$v" ;; esac
}

# THE CLASSIFIER. Its patterns are the instrument, and `--control` exists to prove they match this
# API's real refusal string rather than the one we imagined.
classify_outcome() { # stdin = combined create output; echoes created|refused-quota|refused-other
  local out; out="$(cat)"
  if printf '%s' "$out" | grep -qE 'session_[A-Za-z0-9]+'; then printf 'created'; return 0; fi
  if printf '%s' "$out" | grep -qiE 'usage limit|rate limit|quota|too many|weekly limit|limit reached|exceeded|429'; then
    printf 'refused-quota'; return 0
  fi
  printf 'refused-other'
  return 0
}

# ── THE FOURTH STATE: OUR RIG, NOT THEIR FLEET ──────────────────────────────────────────────────
# Checked BEFORE quota by is_harness_refusal's caller, because a fault in the instrument must never
# be publishable as a property of the accounts. Added 2026-08-08 after the first control run that
# was able to report: the create path is interactive-only, the call was inside `$( )`, and the real
# answer came back "Error: --cloud requires an interactive terminal." With three states that lands
# in `refused-other`, whose control verdict is "✗ classifier WRONG" — convicting the classifier for
# being RIGHT (it correctly declined to call a TTY complaint a quota refusal) while the rig was the
# thing at fault. Same for `script: tcgetattr … not supported on socket`, our own allocator failing.
is_harness_refusal() { # stdin → 0 iff this refusal is about how WE called it
  grep -qiE 'interactive terminal|requires a (tty|terminal)|not a tty|tcgetattr|Operation not supported on socket|pty-run:|unknown option|unrecognized (option|argument)|cannot be combined with|requires a description|no config_dir|no claude binary|no pty allocator|setup GitHub|Bundle upload failed'
}

# Strip the pty's ANSI/OSC/DCS traffic. A pty makes the CLI think a human is watching, so it emits
# colour, cursor moves, bracketed-paste toggles and terminal queries — measured, the raw capture
# rendered `Error:` as `\e[38;2;255;107;128mError:\e[8GBundle\e[15Gupload…`, with cursor-column
# jumps standing in for the SPACES. That defeats any classifier pattern containing a space, and a
# pattern that silently stops matching is worse than no pattern at all.
#
# perl, not sed: BSD sed has no \x escapes and the bracket-class spelling this needs is rejected as
# "unbalanced brackets" — which it reported to stderr while still emitting an EMPTY body, so the
# classifier read '' and the control blamed itself. Loud enough to catch, silent enough to matter.
strip_pty() {
  perl -pe '
      s/\e\][^\a\e]*(?:\a|\e\\)//g;          # OSC
      s/\e[P^_].*?\e\\//g;                     # DCS/PM/APC
      s/\e\[[0-9;]*[GC]/ /g;                    # CHA/CUF are HORIZONTAL MOVEMENT — a SPACE, not a deletion
      s/\e\[[0-9;?<>]*[a-zA-Z]//g;               # every other CSI
      s/\e[()][A-Za-z0-9]//g;                    # charset selection
      s/[\x00-\x08\x0b-\x0d\x0e-\x1f\x7f]//g;  # control chars incl. CR
    ' | tr -s ' '
}

# ── WHY THIS PRINTS A TRAILING NEWLINE, AND WHY EVERY CALLER GUARDS ITS `read` ───────────────────
# `IFS=$'\t' read -r a b < <(fire_one …)` returns 1 when the producer's last line has NO trailing
# newline — the values ARE assigned, but the rc is 1, and under `set -e` that KILLS THE SCRIPT. It
# killed this one: the first `--control` run fired its create, died at the read, and recorded
# nothing. That is the worst possible failure for a probe — it SPENT the attempt and produced no
# evidence, while exiting 0 through `timeout` so it looked like a clean run that simply said little.
# Fixed on both sides deliberately: the newline here so the rc is 0, and `|| true` at each call site
# so a future producer that loses the newline degrades to a recorded reading instead of a silent
# death.
fire_one() { # $1=account $2=label → echoes "<outcome>\t<first-line-of-output>\n"
  local acct="$1" label="$2" cfg out outcome
  cfg="$(config_dir_for "$acct")"
  [ -n "$cfg" ] || { printf 'refused-other\tno config_dir for account %s in %s' "$acct" "$ACCOUNTS_JSON"; return 0; }
  [ -n "$CLAUDE_BIN" ] && [ -x "$CLAUDE_BIN" ] || { printf 'refused-other\tno claude binary (CLOUD_CEILING_CLAUDE_BIN)'; return 0; }
  # ── THE CREATE MUST RUN UNDER A PTY, AND THIS IS NOT A DETAIL ────────────────────────────────
  # Measured 2026-08-08, by this script's own --control:
  #     Error: --cloud requires an interactive terminal. Non-interactive invocations (piped
  #     stdout, --init-only, --sdk-url) run locally and would silently ignore --cloud.
  # A probe captures stdout BY CONSTRUCTION — that is what makes it a probe — so the naive
  # `out="$(… --cloud …)"` is refused on its own capture, every time, on every account. It never
  # reaches the quota question it exists to ask.
  #
  # Note what the refusal says would otherwise happen: the run "would silently ignore --cloud" and
  # execute LOCALLY. So the TTY check is a guard against a far worse failure than the one it
  # causes — a fleet that believes it is off-box while every session runs on this machine, which is
  # the exact opposite of the thing being built. Do not look for a flag to suppress it.
  #
  # `script -q /dev/null <cmd>` allocates a pty and still lets us capture, which is the whole trick.
  # It is BSD `script` (macOS): the command is passed directly, not via -c. Its output carries \r
  # line endings from the pty, stripped below — an unstripped \r rides into the ledger and into
  # every grep the classifier does.
  #
  # The SEND arm needs none of this: §6.3 measured `claude -p … --cloud <id>` delivering with no pty
  # and stdin closed. Create and send are gated differently, and conflating them is how one of these
  # gets a pty it does not need or loses one it does.
  # ⚠️ CORRECTION 2026-08-08, MEASURED: `script(1)` is the right idea and the wrong allocator here.
  # It calls tcgetattr on ITS OWN stdin. From an interactive shell that is a tty and the line above
  # works; from an agent tool call, cron, launchd or CI it is a socket and script dies before ever
  # reaching the child:
  #     script: tcgetattr/ioctl: Operation not supported on socket
  # Which is to say it fails in precisely the contexts a measurement rig is meant to run in, and the
  # classifier then has to read OUR harness fault as a refusal from the account. Measured live while
  # taking the G7 ceiling: the run that produced this comment.
  # scripts/lib/pty-run.py uses pty.openpty(), which needs nothing of the caller's stdin. Verified on
  # the four properties this depends on — the child sees `[ -t 1 ]` true against a same-command
  # control, stdout captured, stderr captured, exit code propagated — plus a timeout so a create that
  # never returns cannot wedge the probe. `script` is kept as the fallback for the interactive case.
  local ptybin ptyrun
  ptyrun="${CLOUD_CEILING_PTY_RUN:-$(dirname "$SELF")/lib/pty-run.py}"
  ptybin="$(command -v script 2>/dev/null || true)"
  # `|| true` on the call, NOT on the classification: a non-zero exit is DATA here (it is how a
  # refusal arrives), and letting errexit kill the ramp would turn the wall into a crash.
  if [ -f "$ptyrun" ] && command -v python3 >/dev/null 2>&1; then
    out="$(PTY_RUN_TIMEOUT_S="${CLOUD_CEILING_CREATE_TIMEOUT_S:-180}" CLAUDE_CONFIG_DIR="$cfg" \
           python3 "$ptyrun" "$CLAUDE_BIN" --cloud "$label" 2>&1 || true)"
  elif [ -n "$ptybin" ]; then
    out="$(CLAUDE_CONFIG_DIR="$cfg" "$ptybin" -q /dev/null "$CLAUDE_BIN" --cloud "$label" 2>&1 || true)"
  else
    out="$(CLAUDE_CONFIG_DIR="$cfg" "$CLAUDE_BIN" --cloud "$label" 2>&1 || true)"
  fi
  # Strip \r AND the pty's ANSI/OSC/DCS traffic, for EVERY branch rather than inside one of them.
  # A pty makes the CLI think a human is watching, so it emits colour, cursor moves,
  # bracketed-paste toggles and terminal queries — measured, the raw capture rendered `Error:` as
  # `[38;2;255;107;128mError:[8GBundle[15Gupload…`, with cursor-column jumps standing in for
  # the SPACES. That defeats any grep with a space in it, and a classifier whose patterns silently
  # stop matching is worse than one that has none.
  # It sits outside the branch because there are now TWO pty allocators: a strip attached to only
  # one of them is a correctness property that holds or not depending on which allocator was
  # available at runtime — exactly the kind of environment-dependent classifier this file keeps
  # being bitten by. On non-pty output it is a no-op.
  out="$(printf '%s' "$out" | strip_pty)"
  if printf '%s' "$out" | is_harness_refusal; then outcome=refused-harness
  else outcome="$(printf '%s' "$out" | classify_outcome)"; fi
  printf '%s\t%s\n' "$outcome" "$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-300)"
}

case "$MODE" in
  report)
    [ -f "$LEDGER" ] || { echo "no ledger at $LEDGER — nothing has been probed"; exit 1; }
    tail -40 "$LEDGER"; exit 0 ;;
  control)
    # Pick a LIMITED account live. Hardcoding one would be a control that silently stops controlling.
    limited="$(claude-accounts --json 2>/dev/null \
      | jq -r '.rows[]? | select((.weekly_pct // 0) >= 99) | .acct' 2>/dev/null | head -1)"
    [ -n "$limited" ] || {
      echo "cloud-ceiling-probe --control: NO account is at ≥99% weekly right now, so there is no"
      echo "  free known-refusal to validate the classifier against. This is a DEFERRAL, not a pass:"
      echo "  do NOT ramp on an unvalidated classifier. Re-run when an account is limited."
      exit 3; }
    echo "control: firing ONE create on '$limited' (weekly $(weekly_pct_for "$limited")%) — expecting refused-quota"
    [ "$CONFIRM" = 1 ] || { echo "  (add --confirm; this spends one create attempt)"; exit 2; }
    assert_capable
    IFS=$'\t' read -r oc msg < <(fire_one "$limited" "ceiling-probe control $(now)") || true
    record "{\"ts\":\"$(now)\",\"kind\":\"control\",\"account\":\"$limited\",\"outcome\":\"$oc\",\"msg\":$(printf '%s' "$msg" | jq -Rs .)}"
    printf 'control outcome: %s\n  %s\n' "$oc" "$msg"
    case "$oc" in
      refused-quota) echo "✓ classifier VALIDATED — a real quota refusal is recognised as one."; exit 0 ;;
      created)       echo "✗ control VOID — the account was not actually limited. Nothing was validated."; exit 4 ;;
      refused-harness)
        # A refusal that never REACHED the quota check indicts the RIG, not the classifier — and
        # saying "classifier WRONG" there sends the next reader to fix the wrong file. This arm
        # exists because the first live control did exactly that: the TTY refusal fires before any
        # account is consulted, so the run carried no information about quota patterns at all.
        #
        # It is now driven by the classifier's own `refused-harness` verdict rather than by a second
        # grep local to this arm. One implementation, so a rig-fault pattern added for the RAMP's
        # benefit cannot silently stop applying to the CONTROL, or vice versa — the drift this repo
        # keeps re-learning (a gate and its report must share the predicate, cf. bin/cc-premise).
        echo "✗ control VOID — the create was refused BEFORE the account was ever consulted:"
        echo "    a precondition of the rig failed, so this run says nothing about the classifier."
        echo "  Fix the rig (the message above names it), then re-run. Do NOT touch classify_outcome."
        exit 7 ;;
      *)
        echo "✗ classifier WRONG — a known quota refusal classified as '$oc'."
        echo "  Fix classify_outcome's patterns against the string above BEFORE ramping."; exit 5 ;;
    esac ;;
esac

[ -n "$ACCOUNT" ] && [ -n "$MAXN" ] || { echo "usage: $0 --account <a> --max <N> --confirm   |   --control --confirm   |   --report" >&2; exit 2; }
case "$MAXN" in ''|*[!0-9]*) echo "--max must be a positive integer" >&2; exit 2 ;; esac
[ "$CONFIRM" = 1 ] || {
  echo "REFUSING: every create spends real weekly quota on account '$ACCOUNT' (now at $(weekly_pct_for "$ACCOUNT")%)."
  echo "  Re-run with --confirm once you accept up to $MAXN creates."; exit 2; }

assert_capable
echo "ramp: account=$ACCOUNT max=$MAXN weekly_before=$(weekly_pct_for "$ACCOUNT")%  ledger=$LEDGER"
record "{\"ts\":\"$(now)\",\"kind\":\"ramp-start\",\"account\":\"$ACCOUNT\",\"max\":$MAXN,\"weekly_before\":\"$(weekly_pct_for "$ACCOUNT")\"}"
created=0; verdict=""; ids=""
for i in $(seq 1 "$MAXN"); do
  IFS=$'\t' read -r oc msg < <(fire_one "$ACCOUNT" "ceiling-probe $i/$MAXN $(now)") || true
  wk="$(weekly_pct_for "$ACCOUNT")"
  record "{\"ts\":\"$(now)\",\"kind\":\"attempt\",\"n\":$i,\"account\":\"$ACCOUNT\",\"outcome\":\"$oc\",\"weekly_after\":\"$wk\",\"msg\":$(printf '%s' "$msg" | jq -Rs .)}"
  printf '  %2d/%s  %-14s weekly=%s%%  %s\n' "$i" "$MAXN" "$oc" "$wk" "$(printf '%s' "$msg" | cut -c1-110)"
  case "$oc" in
    created) created=$((created + 1))
             ids="$ids $(printf '%s' "$msg" | grep -oE 'session_[A-Za-z0-9]+' | head -1)" ;;
    refused-quota) verdict="ceiling"; break ;;
    refused-harness) verdict="harness"; break ;;
    *)             verdict="nonverdict"; break ;;
  esac
done

echo
case "$verdict" in
  ceiling)
    echo "CEILING = $created concurrent creates on '$ACCOUNT' before a quota refusal."
    record "{\"ts\":\"$(now)\",\"kind\":\"verdict\",\"account\":\"$ACCOUNT\",\"verdict\":\"ceiling\",\"n\":$created}" ;;
  harness)
    # Distinct from nonverdict on purpose: "diagnose the refusal" sends a reader to the fleet, and
    # this refusal is about OUR side of the call. Naming it separately is what stops the next reader
    # from re-deriving the TTY/allocator/worktree walls from scratch.
    echo "NON-VERDICT after $created create(s): the ramp stopped on a refusal about HOW IT CALLED"
    echo "  the binary, not about the account. This measures the instrument, not the ceiling —"
    echo "  publish NO number. Fix the rig (see the message above), then re-run from scratch."
    record "{\"ts\":\"$(now)\",\"kind\":\"verdict\",\"account\":\"$ACCOUNT\",\"verdict\":\"harness\",\"n\":$created}" ;;
  nonverdict)
    echo "NON-VERDICT after $created create(s): the ramp stopped on a refusal that was NOT a quota"
    echo "  refusal. Publish NO ceiling from this run — diagnose the refusal above and re-run."
    record "{\"ts\":\"$(now)\",\"kind\":\"verdict\",\"account\":\"$ACCOUNT\",\"verdict\":\"nonverdict\",\"n\":$created}" ;;
  *)
    echo "LOWER BOUND ONLY: $created create(s) succeeded and --max was reached without a refusal."
    echo "  The ceiling is AT LEAST $created on '$ACCOUNT'. This is not the ceiling; the ramp ran out"
    echo "  of budget, not out of quota."
    record "{\"ts\":\"$(now)\",\"kind\":\"verdict\",\"account\":\"$ACCOUNT\",\"verdict\":\"lower-bound\",\"n\":$created}" ;;
esac
[ -n "${ids// /}" ] && {
  echo
  echo "DECLARE these, or they are unobservable AND reapable (CLOUD_OBSERVABILITY.md §5.2):"
  for id in $ids; do [ -n "$id" ] && echo "  cc-cloud declare --id $id --branch <b> --account $ACCOUNT"; done
}
exit 0
