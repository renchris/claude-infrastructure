#!/bin/bash
# shellcheck disable=SC2015  # file-wide: the `<check> && ok || bad` reporter idiom is intentional —
# ok/bad/todo always return 0 (printf + arithmetic), so SC2015's "C runs when A true but B fails" cannot occur.
#
# limit-reset-safety-gate — the RED-provable un-hold bar for the LIMIT-RESET AUTO-RESUME POLLER (B1-d,
# LR-a..LR-h). Sibling of wait-safety-gate.sh / reaper-safety-gate.sh / comms-safety-gate.sh, same
# discipline: criteria REGISTERED before the proof exists; turning this green IS "ready".
#
# ── THE GAP THAT IS THE SPEC (docs/plans/LIMIT_RESET_AUTO_RESUME_POLLER.md) ────────────────────────────
# A session killed by a 5-hour/weekly usage limit stays IDLE FOREVER: the keepalive only nudges RUNNING
# panes; lr-audit parses resets_at_utc but schedules nothing; no launchd job is limit-aware. This is the
# largest hole in the never-stuck-idle invariant (B1-c states: a limit-parked session is neither
# progressing, nor at an owned wait, nor at a designed gate, nor terminated — it is SILENTLY idle with
# work remaining, for hours, exactly when nobody is watching).
#
# ── RECONCILED STATE (2026-07-15) ──────────────────────────────────────────────────────────────────────
# scripts/limit-recover/lr-reset-poller.sh EXISTS (built 2026-07-11/12) and ran a LIVE notify-only cycle
# 2026-07-12 (PARKED 6802c9b8 → READY notified — poller.log). What was MISSING: any RED-provable proof
# (zero tests, no gate row), and the activation is C10-queued (plist NOT in ~/Library/LaunchAgents).
# This gate registers the proof obligations; tests/lr-reset-poller.bats discharges them.
#
# ── ACTIVATED (2026-07-18) — supersedes the "C10-queued" status above ─────────────────────────────────
# The two hand-steps below HAVE BEEN RUN. The plist is installed in ~/Library/LaunchAgents, the job is
# launchctl-loaded, and `launchctl print gui/$(id -u)/com.reso.lr-reset-poller` shows
# LR_POLLER_AUTOFIRE => 1 in the RUNNING job's environment — so unattended auto-resume is LIVE, not
# pending. Receipt: installed 2026-07-18T17:00:15-0700, and RunAtLoad fired a real resume 10s later
# (`2026-07-19T00:00:25Z RESUMED 6802c9b8 … (autofire) — pane opened`). Read the paragraph above as
# history dated 2026-07-15, not as current status.
#
# The LR-d row below still registers "notify-only default" as a proof obligation, and correctly so:
# that is the CODE default when the variable is unset, which the suite must keep proving. It is not a
# claim about the shipped posture — production overrides it in the plist.
#
# ── BUILD-vs-ACTIVATION SPLIT (C10) ────────────────────────────────────────────────────────────────────
# The agent builds + proves the poller; installing the launchd plist and setting LR_POLLER_AUTOFIRE=1
# were OPERATOR hand-steps, ridden via the consolidated wiring-all.sh bundle (docs/activation/
# wiring-all.sh ①) and completed 2026-07-18. The rule is unchanged and still binds: the agent NEVER
# loads launchd or flips autofire itself.
#
# Exit: 0 = every registered criterion met · 1 = not ready (with reasons).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
PASS=0; FAIL=0; TODO=0
ok(){   printf '  ✅ %-7s %s\n' "$1" "$2"; PASS=$((PASS+1)); }
bad(){  printf '  ⛔ %-7s %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }
todo(){ printf '  ⏳ %-7s %s\n' "$1" "$2"; TODO=$((TODO+1)); }

SUITE=tests/lr-reset-poller.bats
POLLER=scripts/limit-recover/lr-reset-poller.sh

echo "limit-reset-safety-gate — never-park-forever bar (LR-a..LR-v registered; RED until $SUITE proves them)"
echo

if [ ! -f "$POLLER" ]; then
  bad "LR-*" "$POLLER ABSENT — the poller itself is gone; the limit-park hole is fully open"
elif [ ! -f "$SUITE" ]; then
  todo "LR-a" "NOT PROVEN — DETECT+LEDGER: a transcript whose tail is a genuine limit isApiErrorMessage (error=rate_limit, reset-bearing) → a PARKED ledger row carrying {kind, reset_at_utc}. RED-provable: fixture transcript → row exists with the parsed reset."
  todo "LR-b" "NOT PROVEN — NO-FIRE-BEFORE-RESET: a parked row whose reset_at_utc is in the FUTURE → no resume, no launcher, no notification (the poller waits)."
  todo "LR-c" "NOT PROVEN — HEADROOM GUARD: reset passed but the account still capped (session_pct/weekly_pct ≥ 100) → WAIT logged, ZERO fire — never resume into a still-capped account (the quota-cliff law: stop, never fire blind)."
  todo "LR-d" "NOT PROVEN — NOTIFY-ONLY DEFAULT + NOTIFY-ONCE: LR_POLLER_AUTOFIRE unset → no session is ever spawned; exactly ONE notification per parked session across N ticks (no per-tick spam)."
  todo "LR-e" "NOT PROVEN — AUTOFIRE + IDEMPOTENT LEDGER: LR_POLLER_AUTOFIRE=1 → launcher written + window-open attempted + the row moves parked/→resumed/ so a second tick NEVER double-fires."
  todo "LR-f" "NOT PROVEN — RUNAWAY CAP: more ready rows than MAX_PER_RUN → only MAX_PER_RUN fire this tick, CAP logged, the rest deferred to the next tick (a detector false-positive cannot spawn unbounded sessions)."
  todo "LR-g" "NOT PROVEN — KILL-SWITCH: LR_POLLER_DISABLED=1 → exit 0 immediately, zero ledger writes, zero fires."
  todo "LR-h" "NOT PROVEN — OUTCOME RECORDS (abstention law): every decision path logs {PARKED|READY|WAIT|RESUMED|CAP} to poller.log — a silent decision is a reaper-shaped detector that cannot be audited."
  todo "LR-i" "NOT PROVEN — RECURRENCE: the resumed/ marker is EVENT-keyed, never sid-keyed-forever. A session resumed once MUST re-park on its NEXT limit event (newer reset ⇒ REPARK); the same event never double-fires. The naive sid-keyed skip is fatal for multi-day runs (a 5h limit recurs every window)."
  todo "LR-j" "NOT PROVEN — HEADLESS SPAWN (P0-8): LR_POLLER_SPAWN=tmux → a parked, reset-passed session resumes via a DETACHED tmux session running the launcher (no Aqua/iTerm2 window) → the ledger moves parked/→resumed/ and the mechanism is recorded. The GUI-only resume is blind in a LaunchDaemon/SSH/pre-login context (P0-10)."
  todo "LR-k" "NOT PROVEN — MONTHLY-SPEND PACKET (P0-8 / I-LIVE-1): a billing-plane kill (\"You've hit your monthly spend limit\", NO reset) → a class-B decision packet via cc-decide (cross-account-continuation default, operator decision #3), and the session is NEVER parked (nothing to wait for) and NEVER silently dropped (the pre-2026-07-19 poller's session|weekly pre-filter dropped it entirely)."
  todo "LR-l" "NOT PROVEN — SPEND IDEMPOTENCY: the class-B spend packet is opened EXACTLY ONCE across N ticks (marker-keyed under spend-packet/) — no per-tick cc-decide spam."
  todo "LR-m" "NOT PROVEN — AUTO FALLBACK: LR_POLLER_SPAWN=auto with the GUI unavailable (osascript window-open fails) → the resume FALLS BACK to tmux rather than logging ERROR and stranding the session — a resume is never silently failed when a headless path exists."
  todo "LR-n" "NOT PROVEN — SPEND TEAMMATE-SKIP: a teammate (agentName) monthly-spend session opens NO packet (recovery is lead-owned; the lead's own spend kill carries the packet) — teammate-skip logged."
  todo "LR-o" "NOT PROVEN — TEXT IS NOT EVIDENCE: a HEALTHY session whose only limit text is the limit-recover skill description (skill_listing attachment, no isApiErrorMessage envelope) opens NO packet, parks nothing, and is not misfiled as a teammate. RED-provable: the pre-2026-07-25 poller opened a false class-B packet off that text alone (incident: fb1d3fc8 + a402c9f3 on next4)."
  todo "LR-p" "NOT PROVEN — NO SPEND SHADOWING: a session carrying BOTH the skill-listing text and a genuine reset-bearing session|weekly kill is still PARKED. RED-provable: the spend branch matched the listing text and hit an unconditional 'continue', so the real kill was never evaluated."
  todo "LR-q" "NOT PROVEN — RECORD FIELDS ARE DATA (codex-security finding 1, medium): a parked record whose cwd carries \$(…) or a backtick is READ, never executed. RED-provable: the pre-2026-07-30 reader was \`eval \"\$(python3 … json.dumps …)\"\`, and json.dumps escapes \" and \\ but NOT \$/backtick — a legal APFS directory name detonated inside a LOADED launchd job."
  todo "LR-r" "NOT PROVEN — FAIL CLOSED ON A BAD RECORD: an unreadable/malformed parked record is SKIPPED with a logged outcome, never processed with half-assigned fields carrying stale values from the previous loop iteration (the abstention law applied to the reader)."
  todo "LR-s" "NOT PROVEN — GENERATED LAUNCHER QUOTING: the resume launcher is bash SOURCE, so every interpolated field must be %q. Executing it must pass cwd VERBATIM as ONE argv element. RED-provable: the pre-2026-07-30 printf spent its only %q on the /limit-recover CONSTANT and gave the three record-derived fields %s inside literal double quotes, so cwd re-expanded when the launcher ran."
  todo "LR-t" "NOT PROVEN — HINT MATCHES REASON: the notify branch is reached both when autofire is OFF and when autofire is ON with --dry-run; the hint it emits must name the ACTUAL reason. RED-provable: the pre-2026-07-30 poller emitted 'Set LR_POLLER_AUTOFIRE=1 to auto-resume' in BOTH cases, i.e. it told the production operator to set a variable already set to 1."
  todo "LR-u" "NOT PROVEN — --dry-run IS POSITIONAL-INDEPENDENT: --dry-run suppresses the fire in ANY argument position, and an unknown argument is REFUSED (exit 2) rather than silently ignored. RED-provable: the pre-2026-07-30 parser inspected only \$1, so \`--once --dry-run\` silently RAN FOR REAL and spawned live sessions while the operator had asked for a preview."
  todo "LR-v" "NOT PROVEN — SSOT PAIR (plist ↔ header): the committed com.reso.lr-reset-poller.plist and the poller's own SHIPPED-POSTURE header marker declare the SAME autofire value, and the plist ACTIVELY sets it. RED-provable: re-commenting the EnvironmentVariables block (the pre-4b0efff2 shape) reads as absent via plistlib and fails. Why registered: launchd-parity-lint.sh chains live == plist but is blind to PROSE in siblings, which is how the header kept saying 'OFF by default' for 12 days after autofire went live."
else
  if command -v bats >/dev/null 2>&1; then
    # `</dev/null`: bats INHERITS stdin into every test, so a suite stubbing a stdin-consuming binary
    # with an unconditional `cat` hangs forever when stdin never EOFs (5e460544 measured rc 124;
    # ce13bd08 fixed the landing runners). MEASURED 2026-08-06: launchd already hands /dev/null, so
    # the exposed path is the one this gate actually runs on — a session/desk invocation, whose fd 0
    # is a unix socket a child reads without ever seeing EOF. This gate reads no stdin of its own.
    # THREE states, not two (item 38e4601fa933, 2026-08-08). `bats` on PATH is a symlink to
    # bin/cc-bats, whose ADMISSION BOUND (added 2026-08-06) exits **75** — EX_TEMPFAIL — over a
    # stderr line this call discards: "nothing ran, nothing was verified — this is a DEFERRAL, not
    # a test result". Treating that as RED (which the bare `if bats …; then/else` did) manufactures
    # a failed-count from criteria that never executed: measured on this box 2026-08-08 at 1-min
    # load 22 on 10 cores, this gate reported "0 met · 1 failed" in ZERO seconds while $SUITE runs
    # 23/23 green in 23s the moment a bats slot frees. nightly-regression.sh already models exactly
    # this idea for rc 124/137/143 (NON-VERDICT — a check that could not RUN is not a failure); 75
    # is a new member of that enum which landed in the `else → RED` arm (memory:
    # new-enum-member-falls-into-fail-closed-default), so the deferral was being laundered into a
    # *bar count* that the runner then compared against a declared baseline. Propagate it instead.
    bats "$SUITE" </dev/null >/dev/null 2>&1; BRC=$?
    if [ "$BRC" -eq 75 ]; then
      echo "  ⏸️ LR-a..v $SUITE DEFERRED — cc-bats admission bound refused (rc 75); nothing ran, nothing verified"
      echo
      echo "⇒ NON-VERDICT: the registered proof never RAN, so this gate has no opinion about the bar"
      echo "  right now. No tally is printed — a count assembled from unexecuted criteria is not a bar."
      exit 75
    elif [ "$BRC" -eq 0 ]; then
      ok "LR-a..v" "$SUITE GREEN — detect+ledger, no-fire-before-reset, headroom guard, notify-only default + notify-once, autofire idempotency, runaway cap, kill-switch, outcome records, event-keyed recurrence, headless tmux spawn (LR-j) + auto→tmux fallback (LR-m), monthly-spend class-B packet (LR-k) + idempotency (LR-l) + teammate-skip (LR-n), and the 2026-07-25 false-positive pair — envelope-required detection (LR-o) + no spend-branch shadowing of a real kill (LR-p), and the 2026-07-30 injection triad — parked-record fields read as DATA not code (LR-q), fail-closed on a malformed record (LR-r), %q-quoted launcher argv (LR-s), plus the posture-honesty trio â hint-matches-reason (LR-t), positional-independent --dry-run + unknown-arg refusal (LR-u, which fixed a silent REAL run), and the SSOT-pair ratchet (LR-v: plist â header cannot drift) â all proven (fixtures = real transcript bytes; stubs for claude-accounts/osascript/tmux/cc-decide; suite RED-proven against the as-shipped poller: LR-c blind headroom + LR-i forever-skip fired, and LR-j/k RED against the GUI-only + session|weekly-only poller)"
    else
      bad "LR-a..v" "$SUITE RED — a registered limit-reset criterion fails (run: bats $SUITE)"
    fi
  else
    bad "LR-*" "bats unavailable — the proof cannot run (install bats-core)"
  fi
fi

# LR-blind — DECLARED, not closed (composition rule: every blindness names its cover):
#   The FABLE-scoped limit message's verbatim shape has never been captured (no real fixture exists).
#   lr-audit classifies by prefix ("You've hit your session|weekly limit…"); IF the Fable message carries
#   the weekly prefix it parks as kind=weekly (covered). IF it has a novel shape it classifies
#   other_api_error → NEVER PARKED → this poller is blind to it. COVER: the session renders STALL?/idle on
#   cc-board and the page-only supervisor pages it (the never-stuck composition holds through a different
#   layer, at page latency instead of reset latency). OBLIGATION: the first real Fable-limit capture must
#   be fixture-ized into $SUITE (turning this declared blindness into a proven row).
echo
echo "  🕳  LR-blind DECLARED: fable-scoped message shape unverified — covered by the weekly prefix if it matches,"
echo "      else by the supervisor stall page (never-stuck composition). Fixture-ize on first real capture."

echo
printf 'limit-reset-safety-gate: %d met · %d failed · %d NOT PROVEN\n' "$PASS" "$FAIL" "$TODO"
if [ "$FAIL" -gt 0 ] || [ "$TODO" -gt 0 ]; then
  echo "⇒ LIMIT-RESET AUTO-RESUME: NOT READY. (Red here is not a bug — it is the bar. Prove LR-a..LR-h in $SUITE.)"
  exit 1
fi
echo "⇒ every registered limit-reset criterion is mechanically proven; the poller is build-complete AND LIVE (activation done 2026-07-18: plist installed, launchd-loaded, LR_POLLER_AUTOFIRE=1 in the running job's env — unattended auto-resume is ON, not queued)."
