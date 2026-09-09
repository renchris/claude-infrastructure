#!/usr/bin/env bats
# permission-harvest WIRING — the weekly cron for bin/cc-permission-harvest, proven at its seams.
#
# Subject: scripts/permission-harvest-run.sh + launchd/com.claude.permission-harvest.plist + the
# fleet.manifest row (docs/plans/PERMISSION_HARVEST.md §5). The harvester itself is NOT under test
# here — it is stubbed through CC_PERMHARVEST_BIN by a fake that writes a proposal of a given shape
# and exits a given rc — because this suite's question is narrower and older than the tool's: does
# the thing that RUNS it turn its result into the three durable products the fleet reads?
#
#   1. ONE evidence row per run in the JSONL that is both cc-fleet's S5 sensor (file mtime) and the
#      skill's 8-week trend store — with EXACTLY the §5 fields, and NO row on a contended lock
#      (a `skipped` row would refresh the staleness sensor over a run that measured nothing).
#   2. ONE operator step, the KEY-4 brake recipe: a `cc-backlog needs` whose title varies only in
#      DIGITS week to week (so the brake folds a live row instead of minting a sibling), whose
#      `--run` names the LIVE tool and carries no path and no rule text, and whose `--falsifier`
#      is `--falsify` — the probe whose exit 0 means "nothing left to apply", which is the ONE sense
#      cc-premise reads as "close this row". This suite used to assert that string by COMPARISON
#      only, and the string it compared against was `--check`, whose exit 0 means the opposite; the
#      polarity was inverted on both arms and passed 295 green tests. So the arms below EXECUTE the
#      recorded probe, against both of its answers, and drive the real cc-backlog and the real
#      cc-premise sweep that consume it.
#   3. An EXIT CODE the fleet board can read: 0 for proposed/nothing, 3 for BLIND (the archive
#      oracle is dark — a `proposed=0` there is a lie of omission, and the manifest declares no
#      ok_exits so it lands on S4 FAILING), 1 for everything else, INCLUDING an rc nobody designed
#      (memory: new-enum-member-falls-into-fail-closed-default).
#
# Every deny-shaped assertion is paired with the control that differs by one lever: N=0 ↔ N>0 for
# the row, rc 3 ↔ rc 7 for blind vs error, a live lock holder ↔ a dead one.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  RUN="$REPO/scripts/permission-harvest-run.sh"
  PLIST="$REPO/launchd/com.claude.permission-harvest.plist"
  MANIFEST="$REPO/launchd/fleet.manifest"
  D="$BATS_TEST_TMPDIR"
  export HOME="$D/home"; mkdir -p "$HOME"                 # hermeticity rule 1
  # The band re-exec is proven on its own below; every other test runs the body directly.
  export CC_PERMHARVEST_BANDED=1
  export CC_PERMHARVEST_BIN="$D/fake-harvest.py"
  export CC_PERMHARVEST_OUT="$D/out"
  export CC_PERMHARVEST_EVIDENCE="$D/logs/permission-harvest.jsonl"
  export CC_PERMHARVEST_BACKLOG="$D/fake-backlog"
  export CC_PERMHARVEST_LOCK="$D/state/harvest.lock"
  export CC_PERMHARVEST_LOG="$D/logs/run.log"
  export CC_PERMHARVEST_DAYS=30
  unset CC_PERMHARVEST_PYTHON CC_PERMHARVEST_TASKPOLICY CC_PERMHARVEST_PRUNE_DAYS
  # The beacon's two seams, pinned in setup() and NOT in the one test that drives it. Their
  # defaults are /tmp/cc-permission-pending and $HOME/.claude/autonomy/permission-archive — the
  # LIVE beacon dir lead-supervisor.sh pages from, and the LIVE archive this whole plan mines. A
  # per-test export leaves every other test in the file pointed at both (scripts/
  # test-hermeticity-lint.sh rule 5, and rule 1's own rationale: per-test pinning is not pinning).
  export CC_PERMPEND_DIR="$D/permpend"
  export CC_PERMARCHIVE_DIR="$D/permarchive"
  export FAKE_ARGV="$D/harvest.argv"
  export FAKE_BACKLOG_ARGV="$D/backlog.argv"
  unset FAKE_RC FAKE_N FAKE_CONS FAKE_SHADOWS FAKE_NOFILE FAKE_STAMP FAKE_SHA FAKE_CONS_PRESENT
  # The fake harvester: records how it was invoked, writes a schema-1-shaped proposal (a
  # proposal-<stamp>.json plus the latest.json copy, exactly as §3.1 describes) and exits FAKE_RC.
  cat > "$CC_PERMHARVEST_BIN" <<'PY'
import json
import os
import sys

with open(os.environ["FAKE_ARGV"], "w") as fh:
    fh.write(json.dumps({"executable": sys.executable, "argv": sys.argv}) + "\n")
rc = int(os.environ.get("FAKE_RC", "0"))
if os.environ.get("FAKE_NOFILE") == "1":
    sys.exit(rc)
args = sys.argv[1:]
out = args[args.index("--out") + 1]
n = int(os.environ.get("FAKE_N", "0"))
cons = int(os.environ.get("FAKE_CONS", "0"))
shadows = int(os.environ.get("FAKE_SHADOWS", "2"))
doc = {
    "schema": 1,
    "generated_utc": "2026-09-07T04:17:00Z",
    "tool": {"sha": os.environ.get("FAKE_SHA", "abc123")},
    "inputs": {"rows": 400, "rows_in_window": 300, "sessions_in_window": 12, "oracle_age_s": 90},
    "buckets": {"structural": 200, "hook_raised": 100, "rule_gap": 40, "ask_hit": 30,
                "deny_hit": 10, "truncated": 20},
    "structural": {"by_kind": {"command_substitution": 120, "heredoc": 80}},
    "proposed": [{"rule": "Bash(gh pr view:*)"} for _ in range(n)],
    "refused": [{"rule": "Bash(bash:*)", "code": "ACE_CLASS"}],
    "consolidation": [{"file": "/x/.claude/settings.local.json", "prefix": "Bash(gh pr view:*)",
                       "shadows": ["a"] * shadows,
                       "present": os.environ.get("FAKE_CONS_PRESENT") == "1"}
                      for _ in range(cons)],
}
os.makedirs(out, exist_ok=True)
stamp = os.environ.get("FAKE_STAMP", "20260907T041700Z")
with open(os.path.join(out, "proposal-%s.json" % stamp), "w") as fh:
    json.dump(doc, fh)
with open(os.path.join(out, "latest.json"), "w") as fh:
    json.dump(doc, fh)
sys.exit(rc)
PY
  # The fake cc-backlog: one CALL marker then argv one per line, appended, so a second call is
  # countable and a value can be read back by the flag that precedes it.
  cat > "$CC_PERMHARVEST_BACKLOG" <<'SH'
#!/bin/bash
{ printf 'CALL\n'; for a in "$@"; do printf '%s\n' "$a"; done; } >> "$FAKE_BACKLOG_ARGV"
[ "${FAKE_BACKLOG_RC:-0}" = 0 ] || exit "$FAKE_BACKLOG_RC"
echo deadbeef0123
SH
  chmod +x "$CC_PERMHARVEST_BACKLOG"
  if ! command -v jq >/dev/null 2>&1; then skip "jq not installed"; fi
}

last_row() { tail -n 1 "$CC_PERMHARVEST_EVIDENCE"; }
field() { last_row | jq -r ".$1"; }
calls() { grep -c '^CALL$' "$FAKE_BACKLOG_ARGV" 2>/dev/null || echo 0; }
# argval <flag> — the argv token that FOLLOWS <flag> in the recorded call
argval() { awk -v k="$1" 'p { print; exit } $0 == k { p = 1 }' "$FAKE_BACKLOG_ARGV"; }
title() { argval needs; }

@test "proposed=0: verdict=nothing, exit 0, NO backlog call, and the denominator rides the row" {
  FAKE_N=0 run bash "$RUN"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CC_PERMHARVEST_EVIDENCE" | tr -d ' ')" -eq 1 ]
  [ "$(field verdict)" = nothing ]
  [ "$(field proposed)" = 0 ]
  [ "$(field rows_in_window)" = 300 ]
  [ "$(field oracle_age_s)" = 90 ]
  [ ! -f "$FAKE_BACKLOG_ARGV" ]
}

@test "N proposed: exactly ONE needs call, and it is the KEY-4 recipe verbatim" {
  FAKE_N=3 run bash "$RUN"
  [ "$status" -eq 0 ]
  [ "$(field verdict)" = proposed ]
  [ "$(field proposed)" = 3 ]
  [ "$(calls)" -eq 1 ]
  [ "$(sed -n 2p "$FAKE_BACKLOG_ARGV")" = needs ]
  t="$(title)"
  [[ "$t" =~ ^Apply\ the\ 3\ harvested\ allow\ rules\ in\ proposal-[0-9TZ]+\.json\ \(proposed\ [0-9]{4}-[0-9]{2}-[0-9]{2}\)$ ]] || false
  [ "$(argval --project)" = claude-infrastructure ]
  # --run names the LIVE tool under $HOME, never the CC_PERMHARVEST_BIN seam, and carries the
  # consent flag cc-do's `bash -c` does not inject (see the wrapper's CONFIRM=1 note). No path
  # into the out dir, no proposal file name, no rule text may ride the queue.
  [ "$(argval --run)" = "CONFIRM=1 $HOME/.claude/bin/cc-permission-harvest --apply" ]
  [ "$(argval --falsifier)" = "$HOME/.claude/bin/cc-permission-harvest --falsify" ]
  # NEVER --check here: same tool, opposite exit sense, and cc-premise closes on 0 (see the arms
  # at the bottom of this file, which execute this recorded string rather than comparing it).
  [[ "$(argval --falsifier)" != *--check* ]] || false
  [[ "$(argval --run)" != *"$CC_PERMHARVEST_OUT"* ]] || false
  [[ "$(argval --run)" != *proposal-* ]] || false
  [[ "$(argval --run)" != *"Bash("* ]] || false
  [[ "$(argval --run)" != *"$CC_PERMHARVEST_BIN"* ]] || false
}

@test "the title varies ONLY in digits between two weeks with different N (the brake's fold key)" {
  FAKE_N=3 FAKE_STAMP=20260907T041700Z run bash "$RUN"
  [ "$status" -eq 0 ]
  t1="$(title)"
  rm -f "$FAKE_BACKLOG_ARGV"
  FAKE_N=12 FAKE_STAMP=20260914T041700Z run bash "$RUN"
  [ "$status" -eq 0 ]
  t2="$(title)"
  [ "$t1" != "$t2" ]
  [ "$(printf '%s' "$t1" | tr -d 0-9)" = "$(printf '%s' "$t2" | tr -d 0-9)" ]
}

@test "proposed=0 with consolidation prefixes STILL files: actionable is proposed + prefixes" {
  FAKE_N=0 FAKE_CONS=2 FAKE_SHADOWS=3 run bash "$RUN"
  [ "$status" -eq 0 ]
  [ "$(field verdict)" = proposed ]
  [ "$(field proposed)" = 0 ]
  [ "$(field consolidation_prefixes)" = 2 ]
  [ "$(field consolidation_retires)" = 6 ]
  [ "$(calls)" -eq 1 ]
  [[ "$(title)" == "Apply the 2 harvested allow rules in "* ]] || false
}

@test "harvester rc 3: verdict=blind, exit 3, no row filed" {
  FAKE_RC=3 FAKE_N=5 run bash "$RUN"
  [ "$status" -eq 3 ]
  [ "$(field verdict)" = blind ]
  [ "$(field rc)" = 3 ]
  [ ! -f "$FAKE_BACKLOG_ARGV" ]
}

@test "an rc nobody designed (7) is verdict=error, exit 1, no row filed — never a success arm" {
  FAKE_RC=7 FAKE_N=5 run bash "$RUN"
  [ "$status" -eq 1 ]
  [ "$(field verdict)" = error ]
  [ "$(field rc)" = 7 ]
  [ ! -f "$FAKE_BACKLOG_ARGV" ]
}

@test "rc 0 with NO latest.json is error, not nothing (a run that wrote nothing measured nothing)" {
  FAKE_NOFILE=1 run bash "$RUN"
  [ "$status" -eq 1 ]
  [ "$(field verdict)" = error ]
  [ "$(field rc)" = 0 ]
}

@test "a missing harvester binary is error with rc 127, exit 1" {
  CC_PERMHARVEST_BIN="$D/no-such-tool" run bash "$RUN"
  [ "$status" -eq 1 ]
  [ "$(field verdict)" = error ]
  [ "$(field rc)" = 127 ]
}

@test "the evidence row carries EXACTLY the section-5 fields, computed from the proposal" {
  FAKE_N=3 FAKE_CONS=1 FAKE_SHADOWS=4 FAKE_SHA=cafe01 run bash "$RUN"
  [ "$status" -eq 0 ]
  want='consolidation_prefixes consolidation_retires hook_raised_share oracle_age_s proposal_path proposed rc refused rows_in_window rule_gap sessions_in_window sha structural_share top_structural_kind ts verdict'
  got="$(last_row | jq -r 'keys | sort | join(" ")')"
  [ "$got" = "$want" ]
  [ "$(field refused)" = 1 ]
  [ "$(field sessions_in_window)" = 12 ]
  [ "$(field structural_share)" = 0.5 ]        # 200 / rows 400
  [ "$(field hook_raised_share)" = 0.25 ]      # 100 / rows 400
  [ "$(field rule_gap)" = 40 ]
  [ "$(field top_structural_kind)" = command_substitution ]
  [ "$(field consolidation_prefixes)" = 1 ]
  [ "$(field consolidation_retires)" = 4 ]
  [ "$(field sha)" = cafe01 ]
  [[ "$(field proposal_path)" == "$CC_PERMHARVEST_OUT/proposal-"*.json ]] || false
  [[ "$(field ts)" =~ ^[0-9]{9,}$ ]] || false
  # one row per run — appended, never rewritten
  FAKE_N=0 run bash "$RUN"
  [ "$(wc -l < "$CC_PERMHARVEST_EVIDENCE" | tr -d ' ')" -eq 2 ]
}

@test "the interpreter is /usr/bin/python3 by default — absolute, never whatever PATH says python3 is" {
  # The tool must run on the interpreter launchd will use, and launchd's PATH resolves `python3`
  # to a different binary than the interactive PATH does (plan §9). The fake records sys.executable,
  # which two invocations of the same binary agree on, and the source pins the default by name.
  FAKE_N=0 run bash "$RUN"
  [ "$status" -eq 0 ]
  expected="$(/usr/bin/python3 -c 'import sys; print(sys.executable)')"
  [ "$(jq -r .executable "$FAKE_ARGV")" = "$expected" ]
  [ "$(jq -r '.argv[1:] | join(" ")' "$FAKE_ARGV")" = "30 --json --out $CC_PERMHARVEST_OUT" ]
  grep -q 'CC_PERMHARVEST_PYTHON:-/usr/bin/python3' "$RUN"
  # …and the seam is the interpreter actually used, so a suite can never silently run the real one
  printf '#!/bin/bash\nprintf "%%s\\n" "$0" > "%s/py.used"\nexec /usr/bin/python3 "$@"\n' "$D" > "$D/py-shim"
  chmod +x "$D/py-shim"
  CC_PERMHARVEST_PYTHON="$D/py-shim" FAKE_N=0 run bash "$RUN"
  [ "$status" -eq 0 ]
  [ "$(cat "$D/py.used")" = "$D/py-shim" ]
}

@test "the --run in the recipe carries no path even when the seams point elsewhere (it names the live tool)" {
  CC_PERMHARVEST_OUT="$D/elsewhere/out" FAKE_N=2 run bash "$RUN"
  [ "$status" -eq 0 ]
  [ "$(argval --run)" = "CONFIRM=1 $HOME/.claude/bin/cc-permission-harvest --apply" ]
  [[ "$(argval --run)" != *elsewhere* ]] || false
}

@test "a backlog call that FAILS is logged, not fatal: the run still reports proposed and exits 0" {
  FAKE_N=2 FAKE_BACKLOG_RC=2 run bash "$RUN"
  [ "$status" -eq 0 ]
  [ "$(field verdict)" = proposed ]
  grep -q 'backlog needs FAILED rc=2' "$CC_PERMHARVEST_LOG"
}

@test "a LIVE lock holder wins: the contender exits 0, writes NO evidence row, leaves the lock alone" {
  mkdir -p "$CC_PERMHARVEST_LOCK"
  echo "$$" > "$CC_PERMHARVEST_LOCK/pid"           # bats's own pid — alive for the whole test
  FAKE_N=3 run bash "$RUN"
  [ "$status" -eq 0 ]
  [ ! -f "$CC_PERMHARVEST_EVIDENCE" ]
  [ ! -f "$FAKE_ARGV" ]                              # the harvester never ran
  [ -d "$CC_PERMHARVEST_LOCK" ]
  [ "$(cat "$CC_PERMHARVEST_LOCK/pid")" = "$$" ]
  grep -q 'skipped: lock held by live pid' "$CC_PERMHARVEST_LOG"
}

@test "a DEAD lock holder is self-healed: the run proceeds and releases the lock at exit" {
  sleep 0.01 & dead=$!; wait "$dead"
  mkdir -p "$CC_PERMHARVEST_LOCK"
  echo "$dead" > "$CC_PERMHARVEST_LOCK/pid"
  FAKE_N=0 run bash "$RUN"
  [ "$status" -eq 0 ]
  [ "$(field verdict)" = nothing ]
  [ ! -d "$CC_PERMHARVEST_LOCK" ]
}

@test "proposal files older than 90 days are pruned; a fresh one and latest.json survive" {
  mkdir -p "$CC_PERMHARVEST_OUT"
  echo '{}' > "$CC_PERMHARVEST_OUT/proposal-20260101T041700Z.json"
  touch -t 202601010417 "$CC_PERMHARVEST_OUT/proposal-20260101T041700Z.json"
  FAKE_N=0 run bash "$RUN"
  [ "$status" -eq 0 ]
  [ ! -f "$CC_PERMHARVEST_OUT/proposal-20260101T041700Z.json" ]
  [ -f "$CC_PERMHARVEST_OUT/proposal-20260907T041700Z.json" ]
  [ -f "$CC_PERMHARVEST_OUT/latest.json" ]
  # the bound is a seam: with a 0-day window yesterday's file goes (proves the prune ran, not the fs).
  # The survivor from the first run is aged one day EXPLICITLY: the cutoff is int(now) and the file
  # was written moments ago, so "older than 0 days" would otherwise hinge on a wall-clock second.
  touch -t "$(date -v-1d '+%Y%m%d%H%M')" "$CC_PERMHARVEST_OUT/proposal-20260907T041700Z.json"
  CC_PERMHARVEST_PRUNE_DAYS=0 FAKE_N=0 FAKE_STAMP=20260908T041700Z run bash "$RUN"
  [ "$status" -eq 0 ]
  [ ! -f "$CC_PERMHARVEST_OUT/proposal-20260907T041700Z.json" ]
  [ -f "$CC_PERMHARVEST_OUT/latest.json" ]
}

@test "the wrapper re-execs itself through taskpolicy -c utility, exactly once, and fails OPEN without it" {
  unset CC_PERMHARVEST_BANDED
  printf '#!/bin/bash\nprintf "%%s\\n" "$@" >> "%s/tp.argv"\nshift 2\nexec "$@"\n' "$D" > "$D/fake-taskpolicy"
  chmod +x "$D/fake-taskpolicy"
  CC_PERMHARVEST_TASKPOLICY="$D/fake-taskpolicy" FAKE_N=0 run bash "$RUN"
  [ "$status" -eq 0 ]
  [ "$(field verdict)" = nothing ]
  [ "$(sed -n 1p "$D/tp.argv")" = -c ]
  [ "$(sed -n 2p "$D/tp.argv")" = utility ]
  [ "$(grep -c '^-c$' "$D/tp.argv")" -eq 1 ]      # the sentinel stopped the recursion
  # no taskpolicy(8) ⇒ the inherited band, not a dead job
  CC_PERMHARVEST_TASKPOLICY="$D/no-such-taskpolicy" FAKE_N=0 run bash "$RUN"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CC_PERMHARVEST_EVIDENCE" | tr -d ' ')" -eq 2 ]
}

@test "plist: plutil -lint clean, weekly calendar, RunAtLoad FALSE, exec through bash -c, literal log paths, no ProcessType/Nice" {
  run /usr/bin/plutil -lint "$PLIST"
  [ "$status" -eq 0 ]
  [ "$(/usr/bin/plutil -extract Label raw -o - "$PLIST")" = com.claude.permission-harvest ]
  [ "$(/usr/bin/plutil -extract StartCalendarInterval.Weekday raw -o - "$PLIST")" = 0 ]
  [ "$(/usr/bin/plutil -extract StartCalendarInterval.Hour raw -o - "$PLIST")" = 4 ]
  [ "$(/usr/bin/plutil -extract StartCalendarInterval.Minute raw -o - "$PLIST")" = 17 ]
  # FALSE, corrected 2026-09-09. It was true on the claim that this job "reads three stores and
  # appends one JSON line"; measured on the live stores the same invocation takes 1,045 s and reads
  # ~8.5 GB, so every bootstrap fired a multi-GB scan holding the wrapper's lock.
  [ "$(/usr/bin/plutil -extract RunAtLoad raw -o - "$PLIST")" = false ]
  [ "$(/usr/bin/plutil -extract ProgramArguments.0 raw -o - "$PLIST")" = /bin/bash ]
  [ "$(/usr/bin/plutil -extract ProgramArguments.1 raw -o - "$PLIST")" = -c ]
  [ "$(/usr/bin/plutil -extract ProgramArguments.2 raw -o - "$PLIST")" = 'exec "$HOME/.claude/scripts/permission-harvest-run.sh"' ]
  [ "$(/usr/bin/plutil -extract StandardOutPath raw -o - "$PLIST")" = /Users/chrisren/.claude/logs/permission-harvest.out.log ]
  [ "$(/usr/bin/plutil -extract StandardErrorPath raw -o - "$PLIST")" = /Users/chrisren/.claude/logs/permission-harvest.err.log ]
  ! grep -q '<key>ProcessType</key>' "$PLIST" || false
  ! grep -q '<key>Nice</key>' "$PLIST" || false
}

@test "manifest: the row parses to six columns with interval 604800; the header says what 0 means" {
  row="$(grep -E '^com\.claude\.permission-harvest[[:space:]]*\|' "$MANIFEST")"
  [ -n "$row" ]
  [ "$(printf '%s\n' "$row" | wc -l | tr -d ' ')" -eq 1 ]
  ncol="$(printf '%s' "$row" | awk -F'|' '{ print NF }')"
  [ "$ncol" -ge 6 ]
  col() { printf '%s' "$row" | awk -F'|' -v n="$1" '{ gsub(/^[ \t]+|[ \t]+$/, "", $n); print $n }'; }
  [ "$(col 2)" = run ]
  [ "$(col 3)" = 604800 ]
  # shellcheck disable=SC2088  # the UNEXPANDED `~/` is the assertion: the manifest stores the tilde
  #                              literally and cc-fleet expands it at read time (fleet.manifest
  #                              header, `evidence`). An expanded $HOME here would pin this box.
  [ "$(col 4)" = '~/.claude/logs/permission-harvest.jsonl' ]
  [ "$(col 5)" = 6 ]
  [ "$(col 6)" = 18-fleet-activate.sh ]
  # the header sentence: 0 = DAILY, and a weekly calendar job declares 604800
  head -40 "$MANIFEST" | grep -q '`0` means DAILY'
  head -40 "$MANIFEST" | grep -q 'WEEKLY calendar job declares its real period, 604800'
  # the wrapper's evidence path IS the manifest's evidence column (one sensor, one file)
  grep -q 'CC_PERMHARVEST_EVIDENCE:-\$HOME/.claude/logs/permission-harvest.jsonl' "$RUN"
}

@test "beacon: the archive cap default is 12000 bytes — a 9 KB command archives whole, a 13 KB one truncates" {
  # §5 (c): at the old 3500 B cap, 84 rows / 126 h reached the harvester as `truncated`, i.e. commands
  # whose text could not be classified at all. The cap was sized for a 4 KiB atomic-append regime
  # that D2b measured false; the mkdir lock serializes appends now, so the cap only decides how much
  # evidence survives. Both halves are asserted so the number is pinned from both sides.
  B="$REPO/hooks/cc-permission-beacon.sh"
  unset CC_PERMARCHIVE_MAXLEN CC_PERMISSION_BEACON_DISABLED
  grep -q 'CC_PERMARCHIVE_MAXLEN:-12000' "$B"
  nine="$(/usr/bin/python3 -c 'print("y" * 9000)')"
  jq -nc --arg c "$nine" '{session_id:"s-nine",tool_name:"Bash",tool_input:{command:$c},cwd:"/w"}' | "$B" write
  jq -nc --arg c "$nine" '{session_id:"s-nine",hook_event_name:"PostToolUse",tool_name:"Bash",tool_input:{command:$c}}' | "$B" clear
  row="$(cat "$CC_PERMARCHIVE_DIR"/*.jsonl | jq -c 'select(.session_id == "s-nine")')"
  [ -n "$row" ]
  [ "$(printf '%s' "$row" | jq -r '.tool_input_truncated // false')" = false ]
  [ "$(printf '%s' "$row" | jq -r '.tool_input.command | length')" -eq 9000 ]
  thirteen="$(/usr/bin/python3 -c 'print("y" * 13000)')"
  jq -nc --arg c "$thirteen" '{session_id:"s-thirteen",tool_name:"Bash",tool_input:{command:$c},cwd:"/w"}' | "$B" write
  jq -nc --arg c "$thirteen" '{session_id:"s-thirteen",hook_event_name:"PostToolUse",tool_name:"Bash",tool_input:{command:$c}}' | "$B" clear
  row="$(cat "$CC_PERMARCHIVE_DIR"/*.jsonl | jq -c 'select(.session_id == "s-thirteen")')"
  [ "$(printf '%s' "$row" | jq -r '.tool_input_truncated')" = true ]
}

# ── THE OPERATOR STEP, DRIVEN RATHER THAN SPELLED (added 2026-09-09) ─────────────────────────────
#
# Every arm above this line stubs cc-backlog with an argv recorder, so what it proves is the TEXT of
# the KEY-4 recipe. That is necessary and it is not sufficient: the one field whose VALUE decides
# whether the weekly loop delivers anything — the `--falsifier` — was asserted by string equality
# against `--check`, and `--check`'s exit sense is the inverse of the one cc-premise acts on. A
# string comparison cannot tell a probe from its negation, which is exactly how the defect passed.
# These four arms run the real consumers instead: the recorded probe through `/bin/sh -c` (how
# `bin/cc-premise:1391` runs it), the real bin/cc-backlog for the brake, and the real
# `cc-premise sweep --record --close-falsified` for the close. All hermetic — $HOME and
# CC_BACKLOG_FILE are the only seams they need.

# The live-tool path the queued row names, made real under the redirected HOME by symlinking the
# repo's tool (realpath resolution finds hooks/lib through the link, which is how the deployed
# per-file symlink works too).
live_tool() {
  mkdir -p "$HOME/.claude/bin"
  ln -sf "$REPO/bin/cc-permission-harvest" "$HOME/.claude/bin/cc-permission-harvest"
  printf '{"permissions":{"allow":[]}}\n' > "$HOME/.claude/settings.json"
}

@test "the recorded --falsifier is EXECUTED, and exits 0 in exactly one direction: nothing left to apply" {
  FAKE_N=3 run bash "$RUN"
  [ "$status" -eq 0 ]
  probe="$(argval --falsifier)"
  live_tool
  # (a) the rule is NOT in the fleet file: work outstanding ⇒ non-zero ⇒ cc-premise leaves the row
  #     LIVE. Under the shipped `--check` this direction returned 0 and the row was auto-closed.
  run /bin/sh -c "$probe"
  [ "$status" -eq 1 ]
  [[ "$output" == *"outstanding"* ]] || false
  # (b) the rule IS present: nothing left to write ⇒ exit 0 ⇒ cc-premise CLOSES the row, correctly.
  printf '{"permissions":{"allow":["Bash(gh pr view:*)"]}}\n' > "$HOME/.claude/settings.json"
  run /bin/sh -c "$probe"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing outstanding"* ]] || false
  # (c) the consumer's contract, read from the consumer — so a polarity flip on EITHER side reddens.
  grep -q 'exit 0     the condition is GONE' "$REPO/bin/cc-premise"
}

@test "the recorded --falsifier fits cc-premise's 20 s probe bound, and fails CLOSED when it cannot tell" {
  # A probe slower than FALSIFIER_TIMEOUT_S does not fail strict — run_falsifier returns None and
  # the signal is silently absent. The full pipeline measured 1,045 s on the live stores, which is
  # why the stored probe is `--falsify` (settings-only) and not `--check` (whole pipeline).
  FAKE_N=2 run bash "$RUN"
  [ "$status" -eq 0 ]
  probe="$(argval --falsifier)"
  live_tool
  grep -q 'FALSIFIER_TIMEOUT_S = int(os.environ.get("CC_PREMISE_FALSIFIER_TIMEOUT", "20"))' "$REPO/bin/cc-premise"
  local t0 t1
  t0="$SECONDS"
  run /bin/sh -c "$probe"
  t1="$SECONDS"
  [ "$status" -eq 1 ]
  [ "$((t1 - t0))" -lt 10 ]
  # fail-closed: no proposal at all is "cannot tell", NOT "discharged"
  rm -f "$CC_PERMHARVEST_OUT/latest.json"
  run /bin/sh -c "$probe"
  [ "$status" -eq 1 ]
  [[ "$output" == *"CANNOT TELL"* ]] || false
}

@test "two weeks through the REAL cc-backlog fold onto one row, and the REAL cc-premise sweep closes it only when discharged" {
  export CC_BACKLOG_FILE="$D/backlog.jsonl"
  : > "$CC_BACKLOG_FILE"
  CC_PERMHARVEST_BACKLOG="$REPO/bin/cc-backlog" FAKE_N=3 FAKE_STAMP=20260907T041700Z run bash "$RUN"
  [ "$status" -eq 0 ]
  CC_PERMHARVEST_BACKLOG="$REPO/bin/cc-backlog" FAKE_N=12 FAKE_STAMP=20260914T041700Z run bash "$RUN"
  [ "$status" -eq 0 ]
  # ONE row across both weeks — the KEY-4 brake, proven against the code that implements it rather
  # than against a `tr -d 0-9` property of the title.
  run python3 -c 'import json, os, sys
ids = set()
for line in open(os.environ["CC_BACKLOG_FILE"]):
    ids.add(json.loads(line).get("id"))
print(" ".join(sorted(i for i in ids if i)))'
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  row="$output"
  [ -n "$row" ]
  live_tool
  # SWEEP 1 — work outstanding. The row must SURVIVE. This is the arm that would have failed on the
  # shipped wiring: `--check` exits 0 here, and the sweep closes on 0.
  run python3 "$REPO/bin/cc-premise" sweep --record --close-falsified 5
  [ "$status" -eq 0 ]
  run bash -c 'python3 -c "import json,os,sys
print(any(json.loads(l).get(\"event\") == \"done\" for l in open(os.environ[\"CC_BACKLOG_FILE\"])))"'
  [ "$output" = False ]
  # SWEEP 2 — the operator has applied it. NOW the row closes itself, which is the whole point of
  # storing a falsifier at all.
  printf '{"permissions":{"allow":["Bash(gh pr view:*)"]}}\n' > "$HOME/.claude/settings.json"
  run python3 "$REPO/bin/cc-premise" sweep --record --close-falsified 5
  [ "$status" -eq 0 ]
  [[ "$output" == *"$row"* ]] || false
  run bash -c 'python3 -c "import json,os,sys
print(any(json.loads(l).get(\"event\") == \"done\" for l in open(os.environ[\"CC_BACKLOG_FILE\"])))"'
  [ "$output" = True ]
}

@test "a consolidation entry already PRESENT in its file is NOT actionable — no row is queued for a no-op" {
  # The emitter counted the GROSS consolidation list while both of the tool's own readers filter
  # `present`. A week whose only consolidation entries were already applied therefore wrote
  # verdict=proposed, queued "Apply the N harvested allow rules", and the operator's cc-do ran
  # --apply, which found nothing wanted, exited 0, and closed the row `done` over a certified no-op.
  FAKE_N=0 FAKE_CONS=2 FAKE_SHADOWS=3 FAKE_CONS_PRESENT=1 run bash "$RUN"
  [ "$status" -eq 0 ]
  [ "$(field verdict)" = nothing ]
  [ ! -f "$FAKE_BACKLOG_ARGV" ]
  # the GROSS count still rides the row: it is the skill's 8-week trend series and shrinking it
  # would rewrite history, so the two quantities are kept apart rather than one serving both.
  [ "$(field consolidation_prefixes)" = 2 ]
  [ "$(field consolidation_retires)" = 6 ]
  # the control — the same shape with `present` false files exactly one row
  rm -f "$CC_PERMHARVEST_EVIDENCE"
  FAKE_N=0 FAKE_CONS=2 FAKE_SHADOWS=3 run bash "$RUN"
  [ "$status" -eq 0 ]
  [ "$(field verdict)" = proposed ]
  [ "$(calls)" -eq 1 ]
}

@test "harvester rc 6 (DEADLINE) is verdict=error, exit 1, no row filed — and the tool declares the bound" {
  # The tool bounds its own read-only pipeline (timeout(1) is not on the stock macOS floor the
  # unattended-path lint ratchets, and the wrapper holds the lock for the whole run).
  FAKE_RC=6 FAKE_N=5 run bash "$RUN"
  [ "$status" -eq 1 ]
  [ "$(field verdict)" = error ]
  [ "$(field rc)" = 6 ]
  [ ! -f "$FAKE_BACKLOG_ARGV" ]
  grep -q 'CC_PERMHARVEST_MAX_S' "$REPO/bin/cc-permission-harvest"
  grep -q 'signal.setitimer' "$REPO/bin/cc-permission-harvest"
}
