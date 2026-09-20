#!/usr/bin/env bats
# bin/cc-limited — the census (LIMIT_DETECT_100P W2b).
#
# THE FIXTURE IS ONE REAL AFTERNOON, FROZEN. `tests/fixtures/lr-2026-09-19/build.sh` reproduces
# five sessions measured on 2026-09-19, each with its real 8-char sid prefix, its real timestamps
# and its real account — and each one a DIFFERENT way the shipped census was wrong. That matters
# more than coverage: a census that gets all five right is not getting them right by accident,
# because no single wrong rule produces five correct answers.
#
# WHAT THE SUITE IS DEFENDING, in one line: the census is a PURE FUNCTION of stores that already
# exist. Nothing rendered as CURRENT — alive, pane owner, moved, engaged, reset_in, cwd_ok — is
# ever stored. C2 at the bottom is the control for exactly that, and it is the only row here that
# can catch a regression into a cached state machine.
#
# HERMETIC: every store is a seam pointing into BATS_TEST_TMPDIR, including `ps` (CC_LIMITED_PS)
# and the clock (LR_NOW). No assertion here reads the mood of the machine running the suite — the
# claim ages, the reset countdowns and the liveness verdicts are all fixed by the fixture.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUBJ="$REPO/bin/cc-limited"
  export CC_FIRE_CAPACITY_GATE=off
  W="$BATS_TEST_TMPDIR/fix"
  bash "$REPO/tests/fixtures/lr-2026-09-19/build.sh" "$W" >/dev/null
  # HOME is fixtured EXPLICITLY, before env.sh is sourced, and not merely as a side effect of it:
  # if build.sh ever fails or changes shape, the fallback must be a broken test, never a suite
  # that quietly starts reading the operator's live ~/.claude stores.
  export HOME="$W/home"
  set -a; . "$W/env.sh"; set +a
  M="$CC_LIMITED_MARKER_DIR"
  CWD_INFRA="$W/Users/chrisren/Development/claude-infrastructure"
}

cc()   { python3 "$SUBJ" "$@"; }
# A MUTANT MUST BE RUN THE WAY THE SUBJECT IS RUN. cc-limited resolves lr_predicate relative to
# its OWN __file__, so a copy written into the tmpdir silently loses its sibling module and dies
# at import — which reads as "the mutant was killed" and would make every control below pass for
# the wrong reason. PYTHONPATH restores the one thing the move broke, and nothing else.
mut()  { local m="$1"; shift; PYTHONPATH="$REPO/scripts/limit-recover" python3 "$m" "$@"; }
jrow() { # $1 = sid prefix, $2 = key  -> that row's value from --json
  cc --all --json | python3 -c '
import json, sys
for r in json.load(sys.stdin)["rows"]:
    if r["sid"].startswith(sys.argv[1]):
        print(r[sys.argv[2]]); break
' "$1" "$2"
}

# ── 1-5: the five sessions ───────────────────────────────────────────────────────────────────────

@test "1 07e30aeb: a 0-assistant STUB under the live account beats a 1.1 MB snapshot elsewhere" {
  # THE COPY-SELECTION TRAP. Three copies exist. The one under the LIVE account's root is three
  # records with zero assistant turns; the one holding the death record is far larger and sits
  # under a different root. "Biggest" and "newest" both name the wrong file — and `cp -p` makes
  # size AND mtime identical across a copy anyway, so neither is even a stable signal.
  # The session is surfaced as RECOVERABLE (stub): named, never dropped, never MOVED.
  run cc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'RECOVERABLE (stub).*#147  07e30aeb' || false
  [ "$(jrow 07e30aeb copies)" = 3 ]
  printf '%s' "$(jrow 07e30aeb tp)" | grep -q 'claude-tertiary.*07e30aeb.*\.jsonl$' || false
}

@test "2 98f02458: a claim 20m old with no live claimant is named, with pid and lock path" {
  # THE STATE NOTHING COULD SEE. A transplant took the lock at 20:53:26Z and its pid is not in the
  # ps table. The shipped census has no concept for this: the session reads as simply gone, so a
  # recovery that produced nothing looks exactly like a recovery that worked.
  run cc
  printf '%s\n' "$output" | grep -q 'FAULT CLAIMED-NOT-LIVE.*98f02458' || false
  printf '%s\n' "$output" | grep -q 'pid 32971' || false
  printf '%s\n' "$output" | grep -q '98f02458-0000-4000-8000-000000000000.lock' || false
  # the age is derived from the PINNED clock, so it is the same number on every box
  printf '%s\n' "$output" | grep -q '20m34s' || false
}

@test "3 a claim younger than the grace window is NOT named" {
  # A live transplant holds its lock for the whole handoff. Naming it as a fault the instant it is
  # taken would report every healthy recovery as a failure — the grace sits above the 90 s
  # dead-wait the launcher already uses.
  python3 - "$LR_STATE_DIR" "$LR_NOW" <<'PY'
import json, sys, datetime
now = datetime.datetime.fromisoformat(sys.argv[2].replace("Z", "+00:00"))
fresh = (now - datetime.timedelta(seconds=60)).strftime("%Y-%m-%dT%H:%M:%SZ")
p = sys.argv[1] + "/locks/98f02458-0000-4000-8000-000000000000.lock"
json.dump({"to": "/x", "ts": fresh, "pid": 32971}, open(p, "w"))
PY
  run cc
  printf '%s\n' "$output" | grep -q '98f02458' || false          # still surfaced…
  run bash -c 'python3 "$1" | grep "FAULT CLAIMED-NOT-LIVE" | grep -c 98f02458 || true' _ "$SUBJ"
  [ "$output" = 0 ]                                              # …but NOT as a fault
}

@test "4 65186f1f: re-engaged on ANOTHER account is grouped where it IS, not where it died" {
  # It died on next3 at 19:58:34Z and a registry row on next2 started at 20:48:39Z, with a real
  # assistant turn after the death. It is settled, and it belongs under next2 — filing it under
  # next3 would queue a recovery for a session that is already working.
  [ "$(jrow 65186f1f group)" = next2 ]
  [ "$(jrow 65186f1f state)" = RE-ENGAGED ]
  run cc
  printf '%s\n' "$output" | grep -q 'settled: 65186f1f #121 RE-ENGAGED' || false
  printf '%s\n' "$output" | grep -q 'moved next3->next2' || false
}

@test "5 09e64dcb: three deaths across two accounts render as ONE row, and its pane was taken" {
  # Two marker FILES hold this session — it capped on next4 twice, then on next3. It is one
  # session and must render once. Its pane 111 now belongs to cb29ae36 (started 22:36:06Z), so the
  # old pane is NOT a recovery target; spawn-at-reset is.
  run cc
  [ "$(printf '%s\n' "$output" | grep -c '09e64dcb')" -eq 1 ]
  printf '%s\n' "$output" | grep -q 'PANE-REUSED .*#111  09e64dcb ×3' || false
  printf '%s\n' "$output" | grep -q 'held by cb29ae36 since 22:36:06Z' || false
  [ "$(jrow 09e64dcb accts)" = "['next4', 'next3']" ]
  run bash -c 'python3 "$1" --tsv | grep 09e64dcb | cut -f8' _ "$SUBJ"
  [ "$output" = "NO-PANE" ]
}

# ── 6-9: the states a naive census gets backwards ────────────────────────────────────────────────

@test "6 one process wearing two hats is RECOVERABLE, not DUPLICATE" {
  # A live registry row AND a `--resume` argv for the same session are usually the SAME process.
  # The shipped census tested the RC of its resume probe instead of counting distinct pids, so one
  # process read as a split brain and the session was parked forever. The union is over PIDs.
  echo "84167 84100 /usr/bin/claude --resume 07e30aeb-0000-4000-8000-000000000000" > "$CC_LIMITED_PROCS"
  run cc
  printf '%s\n' "$output" | grep -q 'RECOVERABLE (stub).*07e30aeb' || false

  # CONTROL: a genuinely SECOND pid must still be caught, or the row above is satisfiable by a
  # census that never reports DUPLICATE at all.
  echo "91111     1 /usr/bin/claude --resume 07e30aeb-0000-4000-8000-000000000000" >> "$CC_LIMITED_PROCS"
  echo "91111 Fri Sep 19 12:00:00 2026" >> "$CC_LIMITED_PS"
  run cc
  printf '%s\n' "$output" | grep -q 'DUPLICATE.*07e30aeb' || false
}

@test "7 an unaddressable death is COUNTED in the footer, never silently dropped" {
  # A marker row with no session id cannot be acted on — but dropping it silently makes the screen
  # claim a completeness it does not have. It is counted where the operator can see it.
  printf '{"ts":"2026-09-19T20:31:00Z","error":"rate_limit","config_dir":"%s","session_id":"?","cwd":"/x","pane":"","last_assistant_message":"cap"}\n' \
    "$HOME/.claude-tertiary" >> "$M/rate_limit__next3.jsonl"
  run cc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '1 unaddressable' || false
  printf '%s\n' "$output" | grep -q '10 marker rows' || false
}

@test "8 a Fable cap is surfaced with NO reset and is not waitable" {
  # 35 real Fable deaths carried no reset time anywhere — not structured, not in prose. The
  # shipped predicates classify this as `other_api_error`, which means NEVER PARKED. Surfacing it
  # with an invented reset would be worse: a row handed to a timer that can never fire stops
  # being visible at all.
  python3 -c '
import json, sys
print(json.dumps({"ts":"2026-09-19T20:45:00Z","error":"rate_limit","config_dir":sys.argv[1],
 "session_id":"2d71c6d8-0000-4000-8000-000000000000","cwd":sys.argv[2],"pane":"","transcript_path":"",
 "last_assistant_message":"You'"'"'ve reached your Fable limit. Run /usage-credits to continue or switch models with /model."}))
' "$HOME/.claude-tertiary" "$CWD_INFRA" >> "$M/rate_limit__next3.jsonl"
  [ "$(jrow 2d71c6d8 cap)" = "model_scoped:Fable" ]
  [ "$(jrow 2d71c6d8 resets_at)" = "None" ]
  [ "$(jrow 2d71c6d8 recoverable_by_waiting)" = "False" ]
  run cc
  printf '%s\n' "$output" | grep -q '2d71c6d8' || false
}

@test "9 cwd checked at READ time: a deleted worktree becomes CWD-GONE" {
  # Measured: 1 -> 3 CWD-GONE inside 20 minutes. A stored `cwd_ok` would have been right when it
  # was written and wrong when it was read, and the two are indistinguishable afterwards.
  rm -f "$LR_STATE_DIR/locks/98f02458-0000-4000-8000-000000000000.lock"
  run cc
  printf '%s\n' "$output" | grep -q 'NO-PANE.*98f02458' || false
  rm -rf "$W/Users/chrisren/Development/.worktrees/wt-pool-2"
  run cc
  printf '%s\n' "$output" | grep -q 'CWD-GONE.*98f02458' || false
}

# ── 10-13: the instrument's own honesty ──────────────────────────────────────────────────────────

@test "10 an unreadable instrument is exit 5 with EMPTY stdout — never an empty list at 0" {
  # THE FAILURE MODE THIS TOOL EXISTS TO END. During a six-pane DNS outage the shipped census
  # printed "(no limit-blocked session anywhere)" — a sentence that is byte-identical to the
  # healthy answer. All four instruments are checked, because any one of them going down produces
  # the same false calm.
  local probe out rc
  for probe in CC_REGISTRY_DIR CC_LIMITED_ACCOUNTS CC_LIMITED_MARKER_DIR CC_LIMITED_PS; do
    rc=0
    out="$(env "$probe=$BATS_TEST_TMPDIR/absent" python3 "$SUBJ" 2>/dev/null)" || rc=$?
    [ "$rc" -eq 5 ]
    [ -z "$out" ]
  done
  # and stderr NAMES which one, so the operator does not have to guess
  run bash -c 'env CC_REGISTRY_DIR=/nope python3 "$1" 2>&1 1>/dev/null' _ "$SUBJ"
  printf '%s\n' "$output" | grep -q 'cc-registry' || false
}

@test "11 a capped marker or an IDL abstain is DEGRADED — rows printed, exit 6" {
  # The marker writer has six paths that write nothing and exit 0, and a capped marker file has
  # stopped recording while looking exactly like a cause that resolved. Either way the enumerator
  # is no longer complete, and a census that cannot say so is asserting a completeness it lost.
  # Rows are still PRINTED — 6 is "degraded", not "broken".
  local out rc=0
  out="$(STOP_FAILURE_CAP=3 python3 "$SUBJ")" || rc=$?
  [ "$rc" -eq 6 ]
  printf '%s\n' "$out" | grep -q 'DEGRADED: rate_limit__next3.jsonl at cap' || false
  printf '%s\n' "$out" | grep -q '07e30aeb' || false        # the rows are still there

  rc=0
  printf '{"ts":"2026-09-19T21:00:00Z","hook":"stop-failure-marker","sid":"x","disposition":"abstained","reason":"no-jq"}\n' \
    > "$CC_LIMITED_IDL"
  out="$(python3 "$SUBJ")" || rc=$?
  [ "$rc" -eq 6 ]
  printf '%s\n' "$out" | grep -q 'IDL abstain' || false
}

@test "12 a network death with a live pane is IDLE-AFTER-ERROR — resume in place, never a move" {
  # Not every dead-in-turn session is capped. Six panes died to one DNS outage and the shipped
  # census reported none of them. The distinction is load-bearing: transplanting a network death
  # spends an account move to fix a problem the account never had.
  printf '{"ts":"2026-09-19T20:40:00Z","error":"server_error","config_dir":"%s","session_id":"07e30aeb-0000-4000-8000-000000000000","cwd":"%s","pane":"147","last_assistant_message":"API Error: getaddrinfo ENOTFOUND api.anthropic.com"}\n' \
    "$HOME/.claude-tertiary" "$W/Users/chrisren/Development/.worktrees/wt-cc-143039-68221" \
    > "$M/server_error__next3.jsonl"
  run cc
  printf '%s\n' "$output" | grep -q 'IDLE-AFTER-ERROR.*07e30aeb' || false
  run bash -c 'python3 "$1" --tsv | grep 07e30aeb | cut -f9' _ "$SUBJ"
  [ "$output" = network ]
}

@test "13 blocked with no registry row and exactly one resume leaf is RESUMING — wait, do not act" {
  rm -f "$LR_STATE_DIR/locks/98f02458-0000-4000-8000-000000000000.lock"
  echo "77777     1 /usr/bin/claude --resume 98f02458-0000-4000-8000-000000000000" > "$CC_LIMITED_PROCS"
  run cc
  printf '%s\n' "$output" | grep -q 'RESUMING.*98f02458' || false
}

# ── 14-15: the window, and the shape of the answer ───────────────────────────────────────────────

@test "14 the default window hides a stale five_hour row and KEEPS a live seven_day one" {
  # A weekly cap outlives any sane --since. Hiding it is how a blocked session becomes invisible
  # for six days — so the window is bypassed for a seven_day row whose reset has not passed.
  # THE RESET MUST COME FROM THE TRANSCRIPT, not the marker: the marker stores only the message
  # text, and prose says "resets 7am" without saying WHICH 7am, so a prose-only read resolves a
  # weekly cap to the morning after the death and the row silently drops out of the window.
  python3 - "$M" "$CWD_INFRA" "$HOME" <<'PY'
import json, os, re, sys
M, CWD, H = sys.argv[1], sys.argv[2], sys.argv[3]
base = H + "/.claude-tertiary"
with open(M + "/rate_limit__next3.jsonl", "a") as f:
    f.write(json.dumps({"ts": "2026-09-14T12:00:00Z", "error": "rate_limit", "config_dir": base,
      "session_id": "aaaa5h00-0000-4000-8000-000000000000", "cwd": CWD, "pane": "",
      "transcript_path": "", "last_assistant_message": "You've hit your session limit"}) + "\n")
    f.write(json.dumps({"ts": "2026-09-16T12:00:00Z", "error": "rate_limit", "config_dir": base,
      "session_id": "bbbb7d00-0000-4000-8000-000000000000", "cwd": CWD, "pane": "",
      "transcript_path": "", "last_assistant_message": "You've hit your weekly limit"}) + "\n")
d = base + "/projects/" + re.sub(r"[^A-Za-z0-9]", "-", CWD)
os.makedirs(d, exist_ok=True)
with open(d + "/bbbb7d00-0000-4000-8000-000000000000.jsonl", "w") as f:
    f.write(json.dumps({"type": "assistant", "isApiErrorMessage": True, "error": "rate_limit",
      "apiErrorStatus": 429, "uuid": "w1", "timestamp": "2026-09-16T12:00:00Z",
      "quotaLimits": {"resetsAt": 1789905600, "rateLimitType": "seven_day"},
      "message": {"model": "<synthetic>",
                  "content": [{"type": "text", "text": "You've hit your weekly limit"}]}}) + "\n")
PY
  run cc
  [ "$(printf '%s\n' "$output" | grep -c 'aaaa5h00')" -eq 0 ]   # 125 h old, reset long passed
  [ "$(printf '%s\n' "$output" | grep -c 'bbbb7d00')" -eq 1 ]   # 3 d old, reset still ahead
  printf '%s\n' "$output" | grep -q 'seven_day · resets 12:00:00Z' || false
  # --all overrides the window in BOTH directions, or the row above would be satisfiable by a
  # census that simply cannot see the stale session at all.
  run bash -c 'python3 "$1" --all | grep -c aaaa5h00' _ "$SUBJ"
  [ "$output" = 1 ]
}

@test "15 the shape of the answer: exit codes, TSV arity, and the two size budgets" {
  # --assert-clean is the machine-readable form of "is there work"; it is a SEPARATE axis from
  # severity, so it never multiplexes with the degraded or unreadable codes.
  run cc --assert-clean
  [ "$status" -eq 1 ]

  # The 11-field TSV is what lr-fleet reads today; the arity and the disposition vocabulary are a
  # compatibility contract, not an implementation detail.
  run bash -c 'python3 "$1" --tsv | awk -F"\t" "{print NF}" | sort -u' _ "$SUBJ"
  [ "$output" = 11 ]
  run bash -c 'python3 "$1" --tsv | cut -f8 | tr "\n" " "' _ "$SUBJ"
  [ "$output" = "RECOVERABLE NO-PANE NO-PANE NO-PANE " ]
  # the settled session is absent from --tsv, matching lf_locate's tail rule
  run bash -c 'python3 "$1" --tsv | grep -c 65186f1f || true' _ "$SUBJ"
  [ "$output" = 0 ]

  # Budgets, because this is read on a 30-column pane and piped into a poller tick.
  run bash -c 'python3 "$1" | wc -c' _ "$SUBJ"
  [ "$output" -le 1200 ]
  # THE BUDGET IS ABOUT PRODUCTION PATH LENGTHS, and the fixture root is a bats tmpdir that is
  # far longer than a real one AND appears inside every stored path. Left raw, this assertion
  # would measure the harness rather than the tool, and it would pass or fail depending on how
  # deep BATS_TEST_TMPDIR happens to sit. So the inflation is subtracted explicitly: each
  # occurrence of the fixture root is re-priced at the length of a real one ("/Users/chrisren").
  local raw occ adj
  raw="$(cc --json | wc -c | tr -d ' ')"
  occ="$(cc --json | grep -o "$W" | wc -l | tr -d ' ')"
  adj=$(( raw - occ * ${#W} + occ * 15 ))
  [ "$occ" -gt 0 ]                       # the correction is real, not a no-op
  [ "$adj" -le 6144 ]

  run cc --sid zzzzzzzz
  [ "$status" -eq 4 ]
  run cc --not-a-flag
  [ "$status" -eq 2 ]
}

# ── the two controls ─────────────────────────────────────────────────────────────────────────────

@test "C1 CONTROL filename_grouping_is_red: grouping by the marker FILE files 65186f1f wrong" {
  # Row 4's whole content is that a moved session is grouped by where it IS. That assertion is
  # only worth something if the obvious wrong rule — group by the file the death was recorded in —
  # actually turns it red. The marker is CAUSE-keyed, so its filename names the account the
  # session LEFT.
  local mutant="$BATS_TEST_TMPDIR/mut-filename.py"
  python3 - "$SUBJ" "$mutant" <<'PY'
import sys
src = open(sys.argv[1]).read()
old = '    row["group"] = row["acct_now"] if (row["acct_now"] and'
assert old in src, "anchor moved"
i = src.index(old)
j = src.index('\n', src.index('else (row.get("acct_death") or "?")', i))
src = src[:i] + '    row["group"] = (death.get("marker_file") or "").split("__")[-1][:-6] or "?"' + src[j:]
open(sys.argv[2], "w").write(src)
PY
  # the mutant must still RUN — a control that dies at import proves nothing
  run mut "$mutant" --all --json
  [ "$status" -eq 0 ]
  run bash -c 'PYTHONPATH="$2" python3 "$1" --all --json | python3 -c "
import json,sys
print([r[\"group\"] for r in json.load(sys.stdin)[\"rows\"] if r[\"sid\"].startswith(\"65186f1f\")][0])"' \
    _ "$mutant" "$REPO/scripts/limit-recover"
  [ "$output" = next3 ]      # RED: the real subject says next2
}

@test "C2 CONTROL stored_liveness_is_red: caching the ps table survives a process dying" {
  # THE INVARIANT, as an executable check. `alive` is DERIVED on every read. A census that stores
  # it — or caches the table it derives it from — keeps reporting a live pane after the process is
  # gone, and there is no later observation that can correct it. This mutant stores exactly that
  # one thing and nothing else, so what turns red is the storing, not a second difference.
  local mutant="$BATS_TEST_TMPDIR/mut-cache.py"
  python3 - "$SUBJ" "$mutant" <<'PY'
import sys
src = open(sys.argv[1]).read()
assert 'def ps_table():' in src and '    return table\n' in src
src = src.replace('def ps_table():',
                  'def ps_table():\n'
                  '    _c = os.environ["MUT_CACHE"]\n'
                  '    if os.path.exists(_c):\n'
                  '        return json.load(open(_c))', 1)
src = src.replace('    return table\n',
                  '    json.dump(table, open(os.environ["MUT_CACHE"], "w"))\n'
                  '    return table\n', 1)
open(sys.argv[2], "w").write(src)
PY
  export MUT_CACHE="$BATS_TEST_TMPDIR/ps.cache"
  # first read: pane 147 is live under both
  run bash -c 'PYTHONPATH="$2" python3 "$1" | grep -c "07e30aeb"' _ "$mutant" "$REPO/scripts/limit-recover"
  [ "$output" = 1 ]
  run cc
  printf '%s\n' "$output" | grep -q 'RECOVERABLE (stub).*#147  07e30aeb' || false

  # the process dies — the ONLY thing that changes
  # Two statements, not `a && b`: under the harness's errexit the right-hand side of `&&` is
  # absorbed, so a failed rewrite here would leave the pid in place and the control would pass
  # while testing nothing.
  grep -v '^84167 ' "$CC_LIMITED_PS" > "$CC_LIMITED_PS.new"
  mv "$CC_LIMITED_PS.new" "$CC_LIMITED_PS"

  # the real subject notices, because it re-derives
  run cc
  [ "$(printf '%s\n' "$output" | grep -c 'RECOVERABLE')" -eq 0 ]
  printf '%s\n' "$output" | grep -qE '(NO-PANE|CWD-GONE).*07e30aeb' || false

  # the mutant does not, and never will — RED
  run bash -c 'PYTHONPATH="$2" python3 "$1" | grep -c "RECOVERABLE (stub)"' _ "$mutant" "$REPO/scripts/limit-recover"
  [ "$output" = 1 ]
}

# ── MEASUREMENTS AND THE MUTANT BATTERY ──────────────────────────────────────────────────────────
# WALL CLOCK, three runs over the 5-session fixture on the cloud VM (Linux, python3 3.11):
#   0.038 0.037 0.038 s.  Budget 0.30 s; the shipped `lr-fleet.sh --locate` it replaces measured 35.5 s.
# That is roughly three orders of magnitude, and it is the whole point rather than a nicety: the
# old census's window was longer than the fleet's own state-change interval, so it described a
# world that had never existed at any instant.
#
# SIZE, same fixture: default screen 896 B (budget 1,200), --json 5.3 KB (budget 6 KB).
#
# MUTANT BATTERY. The rows above are only worth their comments if the suite notices when the rule
# changes, so each load-bearing rule was mutated in bin/cc-limited and the suite re-run from a
# verified 0-not-ok baseline. All five die:
#
#   M1  blocked-ness ignores the copies (always blocked)  -> 4, 15
#   M2  procs sums the two sets instead of UNIONing pids  -> 6
#   M3  liveness drops lstart (a reused pid reads live)   -> C2
#   M4  an unreadable registry returns [] at exit 0       -> 10
#   M5  a capped marker file is not reported              -> 11
#
# M3 landing on C2 rather than on a numbered row is worth reading twice: the invariant control is
# what catches liveness being weakened, because every other row's fixture has a pid that is
# genuinely alive. A suite without C2 would accept pid-reuse blindness silently.
#
# NOT COVERED HERE, and named rather than left to be discovered: W2b row 14, the byte-for-byte
# parity diff against `lf_locate` over tests/lr-fleet.bats's own locate:/D7:/D8: fixtures. It
# belongs with W3, which is where `lf_census` and the --slow-scan path land; asserting parity
# before that plumbing exists would pin this tool against a caller it does not yet have.
