#!/usr/bin/env bash
# permission-harvest-run.sh — the WEEKLY cron for bin/cc-permission-harvest, and nothing else.
#
# WHY THIS FILE EXISTS. The harvester is a read-only reporter over three evidence stores (the
# permission archive, the validate-bash corpus, the settings fleet), and a reporter nobody runs is
# a reporter that does not exist. The failure it prevents is not a wrong number — it is the SILENT
# one: 3,728 Bash permission prompts accrued over months, 1,622 h of wall-clock waiting inside
# them, and no session ever asked the archive what it held, because asking required a human to
# remember to ask. This file is the remembering, and NOTHING ELSE: every gate, every refusal code
# and every rule the proposal contains lives in cc-permission-harvest, which this wrapper only
# parameterises and never second-guesses.
#
# WHAT IT DELIBERATELY DOES NOT DO: apply anything. A weekly job that silently widens the
# permission allowlist is "scripting your own authorization" at machine scale (PERMISSION_HARVEST
# §11). The job PROPOSES, writes one evidence row, and files ONE cc-do-able operator step. The
# apply is the operator's typed `yes`, and hooks/validate-bash.sh denies `--apply` from inside any
# agent session at the chokepoint so this boundary cannot be argued away in prose.
#
# CRITICAL — PATH. System dirs FIRST so the entitled system tools win; Homebrew kept last because
# the box's `jq` lives there and a future reader will reach for it. Nothing below resolves a
# binary by bare name that is not on the stock macOS floor (/usr/bin:/bin:/usr/sbin:/sbin) except
# through an absolute seam — the interpreter is /usr/bin/python3 by absolute path, deliberately:
# launchd's PATH resolves `python3` to Apple's 3.9.6 while the interactive PATH resolves it to
# 3.11.4, and the tool must be exercised on the interpreter that will actually run it (§10 B3-7).
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
set -uo pipefail

# ── BAND. `taskpolicy -c utility` HERE, never `ProcessType Background` in the plist. That key
#    applies Darwin's darwinbg task role, a ONE-WAY floor: every descendant sits at PRI 4 and
#    E-core confined, and `taskpolicy -c utility` from inside cannot climb back out
#    (migrations/0016, tests/postland-band-floor.bats iii). Utility is below interactive and still
#    P-core eligible, which is the band every other actuator in this fleet runs in.
#    Fail-open: no taskpolicy(8) ⇒ run in the inherited band rather than not running at all.
#    The sentinel is what makes the re-exec terminate; `exec` alone would recurse forever. The
#    binary is a seam only so the suite can prove the re-exec happens without touching /usr/sbin.
TASKPOLICY="${CC_PERMHARVEST_TASKPOLICY:-/usr/sbin/taskpolicy}"
if [ "${CC_PERMHARVEST_BANDED:-0}" != "1" ] && [ -x "$TASKPOLICY" ]; then
  export CC_PERMHARVEST_BANDED=1
  exec "$TASKPOLICY" -c utility "$0" "$@"
fi

# ── Seams. Defaults are production; the bats suite overrides every one to stay hermetic. ────────
PYTHON="${CC_PERMHARVEST_PYTHON:-/usr/bin/python3}"
BIN="${CC_PERMHARVEST_BIN:-$HOME/.claude/bin/cc-permission-harvest}"
OUT="${CC_PERMHARVEST_OUT:-$HOME/.claude/autonomy/permission-harvest}"
EVIDENCE="${CC_PERMHARVEST_EVIDENCE:-$HOME/.claude/logs/permission-harvest.jsonl}"
BACKLOG="${CC_PERMHARVEST_BACKLOG:-$HOME/.claude/bin/cc-backlog}"
DAYS="${CC_PERMHARVEST_DAYS:-30}"
PRUNE_DAYS="${CC_PERMHARVEST_PRUNE_DAYS:-90}"
LOCK="${CC_PERMHARVEST_LOCK:-$HOME/.claude/state/permission-harvest.lock}"
LOG="${CC_PERMHARVEST_LOG:-$HOME/.claude/logs/permission-harvest.run.log}"
# `--run` and `--falsifier` name the LIVE tool, never $BIN. $BIN is a test seam and a queued
# operator command must not carry one; the row has to be runnable weeks later from any shell.
LIVE_TOOL="$HOME/.claude/bin/cc-permission-harvest"

case "$DAYS"       in ''|*[!0-9]*) DAYS=30 ;; esac
case "$PRUNE_DAYS" in ''|*[!0-9]*) PRUNE_DAYS=90 ;; esac

mkdir -p "$OUT" "$(dirname "$EVIDENCE")" "$(dirname "$LOG")" "$(dirname "$LOCK")" 2>/dev/null

note() { printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >> "$LOG" 2>/dev/null; }

# ── SINGLETON. RunAtLoad is TRUE (a read-only reporter should seed its evidence at bootstrap), so
#    a login during the Sunday window can start a second copy. Atomic mkdir with a dead-holder
#    self-heal, exactly the shape scripts/worktree-gc-infra-run.sh uses.
#
#    A CONTENDED RUN WRITES NO EVIDENCE ROW, and that is the whole reason this is not a fifth
#    verdict token. `evidence` in launchd/fleet.manifest is this JSONL, and cc-fleet's S5 reads its
#    FILE MTIME — so a `skipped` row would refresh the staleness sensor on a run that measured
#    nothing, which is precisely the fake-success shape the wrapper precedent exists to refuse. The
#    holder is about to write a real row; this copy exits 0 having claimed nothing.
LOCK_HELD=0
if mkdir "$LOCK" 2>/dev/null; then
  LOCK_HELD=1
else
  lpid="$(cat "$LOCK/pid" 2>/dev/null)"
  if [ -n "$lpid" ] && kill -0 "$lpid" 2>/dev/null; then
    note "skipped: lock held by live pid $lpid"
    exit 0
  fi
  rm -rf "$LOCK" 2>/dev/null
  mkdir "$LOCK" 2>/dev/null && LOCK_HELD=1
fi
if [ "$LOCK_HELD" != "1" ]; then
  note "skipped: lock unobtainable"
  exit 0
fi
echo "$$" > "$LOCK/pid" 2>/dev/null
trap 'rm -rf "$LOCK" 2>/dev/null' EXIT INT TERM

# ── The run. The tool is invoked by ABSOLUTE interpreter and its rc is captured verbatim; nothing
#    below re-derives a verdict from its stdout, which is a report for humans and not a contract.
HARVEST_RC=0
if [ ! -f "$BIN" ]; then
  HARVEST_RC=127
  note "harvester missing at $BIN"
else
  "$PYTHON" "$BIN" "$DAYS" --json --out "$OUT" >> "$LOG" 2>&1
  HARVEST_RC=$?
fi

# ── VERDICT + EVIDENCE ROW, in one JSON pass.
#
# ONE PARSER, NOT TWO. The row's fields and the backlog decision both read the same proposal, so
# they are computed in the same program: a shell that re-parsed the JSON for the filing decision
# would be a second oracle over one file, free to disagree with the row it just wrote.
#
# `jq` is deliberately NOT used even though it is on the PATH above: the interpreter is already a
# hard dependency (it just ran the tool), it lives at an absolute path on the stock floor, and
# adding a Homebrew-resolved binary to an unattended path is the class scripts/unattended-path-lint.sh
# exists to ratchet.
#
# rc → verdict is FAIL-CLOSED on an unrecognised code (memory: new-enum-member-falls-into-fail-
# closed-default). The harvester's report mode has exactly two designed codes: 0 = it ran, 3 =
# BLIND (the oracle is dark, so `proposed=0` would be a lie of omission rather than a measurement).
# Every other rc — including a future one — is `error`, never a success arm.
# THE EMITTER IS WRITTEN TO A FILE AND THEN RUN — it is NOT piped through `$(python3 - <<PY …)`.
# /bin/bash here is 3.2.57, whose command-substitution parser scans the heredoc BODY looking for the
# closing `)`, and inside `$( )` an apostrophe opens a quote: one `week's` in a Python COMMENT made
# the whole script die at parse time with `bad substitution: no closing )`. That failure is at PARSE
# time, so it takes the file down before line 1 runs, and it is invisible to every reader who does
# not execute it on this bash. A file has no such coupling, and it also survives an editor that
# re-wraps a comment.
EMITTER="$(dirname "$LOCK")/permission-harvest-emit.$$.py"
trap 'rm -rf "$LOCK" 2>/dev/null; rm -f "$EMITTER" 2>/dev/null' EXIT INT TERM
cat > "$EMITTER" <<'PY'
"""Emit the weekly evidence row, then report the decision back to the wrapper.

Kept in one place so the row and the operator-step decision can never disagree: both are
derived from the same parse of the same proposal file.
"""
from __future__ import annotations

import json
import os
import sys
import time

out_dir, rc_s, evidence, prune_days_s = sys.argv[1:5]
rc = int(rc_s)
prune_days = int(prune_days_s)
now = int(time.time())


def load_latest(d):
    """The proposal the run just wrote, or None when it wrote nothing readable."""
    try:
        with open(os.path.join(d, "latest.json"), "r") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def proposals(d):
    """Every proposal-*.json in the out dir, newest first. Missing dir ⇒ empty, never an error."""
    try:
        names = os.listdir(d)
    except OSError:
        return []
    hits = []
    for n in names:
        if n.startswith("proposal-") and n.endswith(".json"):
            p = os.path.join(d, n)
            try:
                hits.append((os.path.getmtime(p), p))
            except OSError:
                continue
    hits.sort(reverse=True)
    return [p for _, p in hits]


def num(v, default=0):
    return v if isinstance(v, (int, float)) and not isinstance(v, bool) else default


def share(part, whole):
    """A share is None when its denominator is unknown — never 0.0, which reads as 'measured none'."""
    whole = num(whole, 0)
    if whole <= 0:
        return None
    return round(num(part, 0) / float(whole), 4)


data = load_latest(out_dir)

# The proposal FILE this row points at. `latest.json` is a pointer whose name never varies, so it
# cannot key the operator row's title (the KEY-4 brake folds titles differing only in DIGITS, and a
# constant name would fold every week's row onto one that names no week). The newest proposal-*.json
# is the file this run wrote; realpath(latest.json) is the fallback when it is a symlink.
picks = proposals(out_dir)
proposal_path = picks[0] if picks else os.path.realpath(os.path.join(out_dir, "latest.json"))

buckets = data.get("buckets") or {} if data else {}
inputs = data.get("inputs") or {} if data else {}
structural = data.get("structural") or {} if data else {}
by_kind = structural.get("by_kind") or {}
consolidation = data.get("consolidation") or [] if data else []

n_proposed = len(data.get("proposed") or []) if data else 0
n_refused = len(data.get("refused") or []) if data else 0
n_cons = len(consolidation) if isinstance(consolidation, list) else 0
n_retires = 0
# The ACTIONABLE half of the consolidation list — the entries whose prefix is NOT already in its
# target file. THREE readers count this quantity and they must not disagree: the tool's report
# (`len([c for c in cons if not c.get("present")])`) and `--check`/`--apply`'s wanted-set
# (`… and not c.get("present")`) both filter it, and this file used to count the GROSS list. The
# consequence was a certified no-op queued as an operator step: a week whose only consolidation
# entries were already applied still wrote `verdict=proposed`, filed "Apply the N harvested allow
# rules", and the operator's `cc-do` then ran `--apply`, which found nothing wanted, exited 0, and
# closed the row `done` on a step that did nothing. `consolidation_prefixes` below stays GROSS —
# it is the trend store's series and shrinking it would rewrite history — so the two numbers are
# kept separately rather than one being made to serve both jobs.
n_cons_actionable = 0
if isinstance(consolidation, list):
    for c in consolidation:
        if isinstance(c, dict):
            n_retires += len(c.get("shadows") or [])
            if not c.get("present"):
                n_cons_actionable += 1

top_kind = ""
if isinstance(by_kind, dict) and by_kind:
    top_kind = sorted(by_kind.items(), key=lambda kv: (-num(kv[1], 0), kv[0]))[0][0]

# ACTIONABLE is the sum, and that is a decision this file records rather than assumes: A2 measured
# the weekly product as the CONSOLIDATION first (58 prefixes retiring 254 exact acceptances) and
# 0-5 archive rules second, so a week with 0 archive rules and 58 consolidation prefixes is the
# EXPECTED shape and reporting it as `nothing` would hide the main product behind its smallest one.
# The raw archive count survives verbatim in the `proposed` field, so nothing is lost.
actionable = n_proposed + n_cons_actionable

if rc == 3:
    verdict = "blind"
elif rc == 0:
    verdict = "error" if data is None else ("proposed" if actionable > 0 else "nothing")
else:
    verdict = "error"

row = {
    "ts": now,
    "verdict": verdict,
    "rc": rc,
    "proposed": n_proposed,
    "refused": n_refused,
    "rows_in_window": num(inputs.get("rows_in_window"), 0),
    "sessions_in_window": num(inputs.get("sessions_in_window"), 0),
    "oracle_age_s": num(inputs.get("oracle_age_s"), 0),
    "structural_share": share(buckets.get("structural"), inputs.get("rows")),
    "hook_raised_share": share(buckets.get("hook_raised"), inputs.get("rows")),
    "rule_gap": num(buckets.get("rule_gap"), 0),
    "top_structural_kind": top_kind,
    "consolidation_prefixes": n_cons,
    "consolidation_retires": n_retires,
    "proposal_path": proposal_path,
    "sha": ((data.get("tool") or {}).get("sha") or "") if data else "",
}
try:
    d = os.path.dirname(evidence)
    if d:
        os.makedirs(d, exist_ok=True)
    with open(evidence, "a") as fh:
        fh.write(json.dumps(row) + "\n")
except OSError:
    # An unwritable evidence path is a real fault, but it must not turn a completed measurement
    # into a crash: the verdict still reaches the wrapper, which still sets the exit code the
    # fleet board reads. The missing row shows up as S5 STALLED, which is the honest surface.
    sys.stderr.write("permission-harvest-run: evidence append failed: %s\n" % evidence)

# PRUNE. Bounded by age, never by count: the trend store the skill reads is the JSONL above, so a
# proposal file older than the window is a dead artifact and not history.
cutoff = now - prune_days * 86400
for p in picks:
    try:
        if os.path.getmtime(p) < cutoff:
            os.remove(p)
    except OSError:
        continue

# The decision, handed back as parseable k=v so the shell never re-reads the JSON.
sys.stdout.write(
    "VERDICT=%s ACTIONABLE=%d BASENAME=%s DATE=%s\n"
    % (verdict, actionable, os.path.basename(proposal_path),
       time.strftime("%Y-%m-%d", time.gmtime(now)))
)
PY
SUMMARY="$("$PYTHON" "$EMITTER" "$OUT" "$HARVEST_RC" "$EVIDENCE" "$PRUNE_DAYS")"
EMIT_RC=$?

# The emitter itself failing is not a harvester verdict. Report it as `error` and refuse to file:
# a row filed off an unparsed decision is a queued operator command nobody derived.
if [ "$EMIT_RC" -ne 0 ] || [ -z "$SUMMARY" ]; then
  note "verdict=error reason=emitter-failed emit_rc=$EMIT_RC harvest_rc=$HARVEST_RC"
  exit 1
fi

# Read the k=v line with word-splitting rather than `sed … | head -1`: under `set -o pipefail` an
# early-exiting consumer SIGPIPEs its producer and the 141 becomes the pipeline's status
# (scripts/pipefail-sigpipe-lint.sh). `set -f` because a value must never glob against the cwd.
VERDICT=""; ACTIONABLE=0; BASENAME=""; RUN_DATE=""
set -f
for _kv in $SUMMARY; do
  case "$_kv" in
    VERDICT=*)    VERDICT="${_kv#VERDICT=}" ;;
    ACTIONABLE=*) ACTIONABLE="${_kv#ACTIONABLE=}" ;;
    BASENAME=*)   BASENAME="${_kv#BASENAME=}" ;;
    DATE=*)       RUN_DATE="${_kv#DATE=}" ;;
  esac
done
set +f
case "$ACTIONABLE" in ''|*[!0-9]*) ACTIONABLE=0 ;; esac

note "verdict=$VERDICT rc=$HARVEST_RC actionable=$ACTIONABLE proposal=$BASENAME"

# ── THE OPERATOR STEP — the KEY-4 brake recipe (§5, B3-1).
#
# `needs` accepts no `--condition`, so weekly idempotency is bought with the MINT BRAKE instead
# (bin/cc-backlog:3475-3520): a re-file whose title differs from a live row's ONLY IN DIGITS folds
# onto that row and re-blocks it with the new `--run`/`--needs`, so at most one row is ever open.
# That is why the title's non-digit skeleton must not move between weeks — the count, the proposal
# stamp and the date are all digits, and everything else is a literal.
#
# `--run` CARRIES NO PATH AND NO RULE TEXT: the tool resolves latest.json itself, so nothing
# attacker-controllable or stale rides the queue and a row filed weeks ago still applies TODAY's
# proposal (§10 B1-5c).
#
# ⚠ CONFIRM=1 IS ON THE WIRE DELIBERATELY, and it is a correction to the plan's literal recipe.
# §3.3 says consent "is CONFIRM=1, given by the operator's typed yes at the cc-do layer" — but
# bin/cc-do:436 runs `bash -c "$cmd" </dev/null` and injects no CONFIRM anywhere (its CONFIRM=1
# prefix at :350 belongs to the ACTIVATION class, not to a backlog row's `run`). So the plan's bare
# string would have the operator type `yes`, run the tool WITHOUT consent, get §3.3's documented
# `--check` behaviour, exit 0, and have cc-do close the row on that exit — a queue row that reports
# applied and applied nothing, forever. The typed `yes` is still the consent: cc-do PRINTS this
# exact command before asking, so the operator reads the flag they are granting.
# ⚠ --falsifier IS `--falsify`, NOT `--check`, AND THE DIFFERENCE IS THE WHOLE ROW. This line read
# `--check` until 2026-09-09 and its polarity was INVERTED on both arms. `--check` exits 0 when ≥1
# rule WOULD apply (§3.3, and it is a human preview so that is the right sense for it);
# `cc-premise.run_falsifier` reads exit 0 as "the condition this row was filed for is GONE" and
# `sweep --record --close-falsified` — every 6 h, scripts/autonomy-sweep.sh — then CLOSES the row.
# So the wiring said: rules still need applying ⇒ probe exits 0 ⇒ the sweep auto-retires the
# operator's apply step within 6 h of filing it, recording `done` over an apply that never ran; and
# a proposal that decayed to nothing ⇒ probe exits 1 ⇒ "still live" ⇒ the dead row stays open
# forever. Reproduced end-to-end against the real bin/cc-premise (1 row CLOSED, evidence
# "falsifier passed", nothing applied). `--falsify` is the inverse probe built for that contract —
# exit 0 only when nothing is left to write — and it is SETTINGS-ONLY, because FALSIFIER_TIMEOUT_S
# is 20 s (bin/cc-premise:241), a timed-out probe fails OPEN, and this tool's full pipeline was
# measured at 1,045 s. It resolves latest.json, so a decayed week still self-closes the stale row.
if [ "$VERDICT" = "proposed" ] && [ "$ACTIONABLE" -gt 0 ]; then
  if [ -x "$BACKLOG" ] || command -v "$BACKLOG" >/dev/null 2>&1; then
    "$BACKLOG" needs \
      "Apply the $ACTIONABLE harvested allow rules in $BASENAME (proposed $RUN_DATE)" \
      --project claude-infrastructure \
      --run "CONFIRM=1 $LIVE_TOOL --apply" \
      --falsifier "$LIVE_TOOL --falsify" >> "$LOG" 2>&1 \
      || note "backlog needs FAILED rc=$?"
  else
    note "backlog binary missing at $BACKLOG — operator step NOT filed"
  fi
fi

# ── Exit codes ARE the fleet board's verdict. `blind` is 3 and the manifest row declares no
#    `ok_exits`, deliberately: a dark oracle must land on S4 FAILING, because the alternative is a
#    reporter that says `proposed=0` forever and reads exactly like a healthy quiet week (§10 B3-3).
case "$VERDICT" in
  proposed|nothing) exit 0 ;;
  blind)            exit 3 ;;
  *)                exit 1 ;;
esac
