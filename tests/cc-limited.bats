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
  CWD_143039="$W/Users/chrisren/Development/.worktrees/wt-cc-143039-68221"
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

# ── 16-22: the seven rows § 11 added after the synthesis (each names its amendment) ──────────────

@test "16 § 11 #2 a beat-live session with NO registry row is RECOVERABLE at #?, never NO-PANE" {
  # THE FATAL THIS CLOSES. Liveness was single-sourced on the registry, and P5 REFUTED that
  # store's completeness: 3 of 14 rate_limit sids had no row at all. The cause is not addressing —
  # it is that the registry is PANE-KEYED, so a recycled pane OVERWRITES the row of the session
  # that used to hold it. That session is still running; its row is simply gone. A registry-only
  # census calls it NO-PANE and hands it to a recovery path that duplicates a live session.
  #
  # The beat is a different store with a different key: one file per SID, written by
  # session-beat.sh for every session that ever submitted a prompt, and nothing recycles a sid.
  local sid=beat0001-0000-4000-8000-000000000000
  printf '{"ts":"2026-09-19T20:31:00Z","error":"rate_limit","config_dir":"%s","session_id":"%s","cwd":"%s","pane":"","transcript_path":"","last_assistant_message":"You%s"}\n' \
    "$HOME/.claude-tertiary" "$sid" "$CWD_INFRA" "'ve hit your session limit" \
    >> "$M/rate_limit__next3.jsonl"
  # no registry row, no lock, no resume leaf — the ONLY evidence this session exists is its beat
  printf '{"sid":"%s","pane":"","cwd":"%s","pid":66666,"lstart":"Fri Sep 19 12:00:00 2026","t":"2026-09-19T21:10:00Z","seq":4}\n' \
    "$sid" "$CWD_INFRA" > "$CC_BEAT_DIR/$sid.json"
  echo "66666 Fri Sep 19 12:00:00 2026" >> "$CC_LIMITED_PS"

  run cc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'RECOVERABLE .*#\?  *beat0001' || false
  [ "$(jrow beat0001 live)" = True ]
  [ "$(jrow beat0001 procs)" = 1 ]        # UNION, not sum: the beat names the same ancestor
  [ "$(printf '%s\n' "$output" | grep -c 'NO-PANE.*beat0001')" -eq 0 ]

  # the beat's OWN pane is used when it carries one — `#?` is the unknown case, not the only case
  printf '{"sid":"%s","pane":"203","cwd":"%s","pid":66666,"lstart":"Fri Sep 19 12:00:00 2026","t":"2026-09-19T21:10:00Z","seq":5}\n' \
    "$sid" "$CWD_INFRA" > "$CC_BEAT_DIR/$sid.json"
  run cc
  printf '%s\n' "$output" | grep -q 'RECOVERABLE .*#203  *beat0001' || false

  # CONTROL — the beat must not make liveness UNFALSIFIABLE. A beat whose pid is not in the ps
  # table is a record of a session that HAS run, not of one that is running, and the row must fall
  # straight back to NO-PANE. Without this arm row 16 is satisfiable by "a beat means alive",
  # which would re-introduce the stored-liveness bug C2 exists to prevent, through a new door.
  grep -v '^66666 ' "$CC_LIMITED_PS" > "$CC_LIMITED_PS.new"
  mv "$CC_LIMITED_PS.new" "$CC_LIMITED_PS"
  run cc
  printf '%s\n' "$output" | grep -q 'NO-PANE.*beat0001' || false
  [ "$(jrow beat0001 live)" = False ]

  # CONTROL 2 — and not on pid alone either. The pid is back in the table under a DIFFERENT
  # lstart, which is exactly what a reissued pid looks like. (pid,lstart) is the identity.
  echo "66666 Sat Sep 20 08:00:00 2026" >> "$CC_LIMITED_PS"
  run cc
  printf '%s\n' "$output" | grep -q 'NO-PANE.*beat0001' || false
}

@test "17 § 11 #3 a PARKED-only sid is in the census at all, with its cap and its reset" {
  # THE BUG WAS A SILENCE, and it is the worst shape a detection tool can have. `parked_sids()`
  # enumerated the poller's parked/ directory and the only thing the census did with it was set a
  # boolean on rows that already existed — so a session the POLLER knows is blocked, but whose
  # death the marker hook never recorded, was absent from the screen entirely.
  #
  # A parked record carries none of the fields the marker formula reads: no ts, no config_dir, no
  # error, no last_assistant_message. Hence an ADAPTER, and hence "classify by CAP, never by
  # text": the message is empty by construction here, so a text-driven read resolves every parked
  # session to other_api_error — not a limit, not waitable, not recoverable.
  local P="$LR_STATE_DIR/parked"
  printf '{"sid":"%s","acct":"next3","cfg":"%s","cwd":"%s","kind":"session","reset_at_utc":"2026-09-19T21:30:00Z","parked_at":"2026-09-19T21:00:00Z"}\n' \
    "park5h00-0000-4000-8000-000000000000" "$HOME/.claude-tertiary" "$CWD_INFRA" \
    > "$P/park5h00-0000-4000-8000-000000000000.json"
  printf '{"sid":"%s","acct":"next3","cfg":"%s","cwd":"%s","kind":"fable","reset_at_utc":"","parked_at":"2026-09-19T21:02:00Z"}\n' \
    "parkfabl-0000-4000-8000-000000000000" "$HOME/.claude-tertiary" "$CWD_INFRA" \
    > "$P/parkfabl-0000-4000-8000-000000000000.json"

  run cc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'park5h00' || false
  [ "$(jrow park5h00 cap)" = five_hour ]
  [ "$(jrow park5h00 resets_at)" = 1789853400 ]          # 21:30:00Z, from reset_at_utc
  [ "$(jrow park5h00 recoverable_by_waiting)" = True ]
  # the reset is attributable: it came from the poller's field, and calling that "prose" would
  # make a wrong reset untraceable — which is the one thing resets_source exists to prevent
  [ "$(jrow park5h00 resets_source)" = parked ]
  [ "$(jrow park5h00 group)" = next3 ]

  # kind=fable maps to the model-scoped cap and is NOT waitable: 35 real Fable deaths carried no
  # reset anywhere, so a timer handed this row could never fire and the row would vanish instead.
  printf '%s\n' "$output" | grep -q 'parkfabl' || false
  [ "$(jrow parkfabl cap)" = "model_scoped:Fable" ]
  [ "$(jrow parkfabl resets_at)" = None ]
  [ "$(jrow parkfabl recoverable_by_waiting)" = False ]

  # CONTROL: a marker ALWAYS wins. The marker is the richer record — it carries the pane, the
  # transcript path and the death text — and the poller's park is downstream of it, so adopting
  # over the top would BLANK a pane the census had already resolved.
  printf '{"sid":"%s","acct":"next3","cfg":"%s","cwd":"/wrong","kind":"weekly","reset_at_utc":"2026-09-26T00:00:00Z","parked_at":"2026-09-19T21:05:00Z"}\n' \
    "07e30aeb-0000-4000-8000-000000000000" "$HOME/.claude-tertiary" \
    > "$P/07e30aeb-0000-4000-8000-000000000000.json"
  [ "$(jrow 07e30aeb cap)" = five_hour ]                 # the marker's, not the park's weekly
  [ "$(jrow 07e30aeb parked)" = True ]                   # still FLAGGED as parked, just not adopted
}

@test "18 § 11 #4 one session reachable through two roots is copies=1, and the depth is the point" {
  # THE COMMENT THAT WAS FALSE. The shipped dedupe was `realpath(root)` and its comment said
  # "~/.claude-next is a SYMLINK to ~/.claude". It is not: ~/.claude-next is a REAL DIRECTORY with
  # its own settings, and only its `projects/` is the symlink. So the two roots never compared
  # equal, the dedupe never fired, and every transcript reachable through both was counted twice.
  # Nothing went red, because a belief written in a comment is executed by nothing.
  local sid=dupe0001-0000-4000-8000-000000000000
  rm -rf "$HOME/.claude-next"
  mkdir -p "$HOME/.claude-next"
  ln -s "$HOME/.claude/projects" "$HOME/.claude-next/projects"
  mkdir -p "$HOME/.claude/projects/$(printf '%s' "$CWD_INFRA" | sed 's/[^A-Za-z0-9]/-/g')"
  printf '{"type":"system","subtype":"bridge-session"}\n' \
    > "$HOME/.claude/projects/$(printf '%s' "$CWD_INFRA" | sed 's/[^A-Za-z0-9]/-/g')/$sid.jsonl"
  printf '{"ts":"2026-09-19T20:32:00Z","error":"rate_limit","config_dir":"%s","session_id":"%s","cwd":"%s","pane":"","transcript_path":"","last_assistant_message":"You%s"}\n' \
    "$HOME/.claude" "$sid" "$CWD_INFRA" "'ve hit your session limit" \
    >> "$M/rate_limit__next3.jsonl"
  export CC_LIMITED_ROOTS="$HOME/.claude:$HOME/.claude-next:$HOME/.claude-secondary:$HOME/.claude-tertiary:$HOME/.claude-quaternary"

  [ "$(jrow dupe0001 copies)" = 1 ]

  # CONTROL A — the SHIPPED rule, restored in full: dedupe at the root, and no inode pass. That
  # is the code that was on trunk, and it reads 2. Both halves are reverted together HERE on
  # purpose: reverting only the depth leaves the inode pass to catch this fixture, so a
  # depth-only mutant would survive and the control would certify a rule it never exercised.
  # (Measured on the § 5 fixture reshaped to this form before the fix: copies read 5 where 3 exist.)
  local shipped="$BATS_TEST_TMPDIR/mut-shipped-dedupe.py"
  python3 - "$SUBJ" "$shipped" <<'PY'
import sys
src = open(sys.argv[1]).read()
depth = '        real = os.path.realpath(os.path.join(root, "projects"))'
assert depth in src, "anchor moved: root dedupe depth"
assert src.count("    return _distinct_files(hits)") == 2, "anchor moved: inode pass"
src = src.replace(depth, '        real = os.path.realpath(root)', 1)
src = src.replace("    return _distinct_files(hits)", "    return hits")
open(sys.argv[2], "w").write(src)
PY
  run mut "$shipped" --all --json
  [ "$status" -eq 0 ]                    # a control that dies at import proves nothing
  run bash -c 'PYTHONPATH="$2" python3 "$1" --all --json | python3 -c "
import json,sys
print([r[\"copies\"] for r in json.load(sys.stdin)[\"rows\"] if r[\"sid\"].startswith(\"dupe0001\")][0])"' \
    _ "$shipped" "$REPO/scripts/limit-recover"
  [ "$output" = 2 ]                      # RED: the real subject says 1

  # AND THE SECOND HALF, WHICH NEEDS ITS OWN FIXTURE. Root dedupe cannot reach a hard link, a
  # bind mount, or a root under a spelling accounts.json does not list: here the copy is under
  # .claude-secondary, a genuinely different projects/ that no root rule may collapse.
  # (st_dev, st_ino) is the only identity a filesystem guarantees.
  local d="$HOME/.claude-secondary/projects/$(printf '%s' "$CWD_INFRA" | sed 's/[^A-Za-z0-9]/-/g')"
  mkdir -p "$d"
  ln "$HOME/.claude/projects/$(printf '%s' "$CWD_INFRA" | sed 's/[^A-Za-z0-9]/-/g')/$sid.jsonl" \
     "$d/$sid.jsonl"
  [ "$(jrow dupe0001 copies)" = 1 ]

  # CONTROL B — the inode pass ALONE removed, root depth left correct. It reads 2 on the hard
  # link, which is the population the root rule is structurally blind to.
  local noinode="$BATS_TEST_TMPDIR/mut-noinode.py"
  python3 - "$SUBJ" "$noinode" <<'PY'
import sys
src = open(sys.argv[1]).read()
assert src.count("    return _distinct_files(hits)") == 2, "anchor moved: inode pass"
open(sys.argv[2], "w").write(src.replace("    return _distinct_files(hits)", "    return hits"))
PY
  run bash -c 'PYTHONPATH="$2" python3 "$1" --all --json | python3 -c "
import json,sys
print([r[\"copies\"] for r in json.load(sys.stdin)[\"rows\"] if r[\"sid\"].startswith(\"dupe0001\")][0])"' \
    _ "$noinode" "$REPO/scripts/limit-recover"
  [ "$output" = 2 ]                      # RED: the real subject says 1
}

@test "19 § 11 #7 a 500-row marker file is AT CAP — exit 6, rows intact, one row per sid" {
  # § 9 D3 raised CAP to 5000 and § 11 #7 reverses it to 500 and BINDS. The reversal's argument is
  # not "5000 is too big to read" — it is that the two reasons given for it do not reach the cap.
  # (a) A multi-fire sid re-capping does not consume the ceiling, because the census groups PER SID
  # at read time: 493 distinct sids below produce 493 rows, and N re-caps of one sid produce ONE.
  # (b) The TTL argument does not transfer, because the GC is keyed on FILE mtime, so a busy
  # account's marker never expires at any cap. P1 measured peak 271 rows/day fleet-wide against a
  # 500 ceiling — inside 2x, which is a margin, where 5000 is ~350x, which is an unbounded file.
  python3 - "$M" "$HOME" "$CWD_INFRA" <<'PY'
import json, sys
M, H, CWD = sys.argv[1], sys.argv[2], sys.argv[3]
with open(M + "/rate_limit__next3.jsonl", "a") as f:
    for i in range(493):                       # 7 rows already present -> exactly 500
        f.write(json.dumps({"ts": "2026-09-19T20:%02d:%02dZ" % (i // 60, i % 60),
          "error": "rate_limit", "config_dir": H + "/.claude-tertiary",
          "session_id": "cafe%04d-0000-4000-8000-000000000000" % i, "cwd": CWD,
          "pane": "", "transcript_path": "",
          "last_assistant_message": "You've hit your session limit"}) + "\n")
PY
  [ "$(wc -l < "$M/rate_limit__next3.jsonl" | tr -d ' ')" = 500 ]

  local out rc=0
  out="$(cc)" || rc=$?
  [ "$rc" -eq 6 ]                                        # at cap == DEGRADED, by design
  printf '%s\n' "$out" | grep -q 'DEGRADED: rate_limit__next3.jsonl at cap' || false
  printf '%s\n' "$out" | grep -q '07e30aeb' || false     # rows are still PRINTED at 6

  # per-sid grouping, asserted rather than assumed: 498 sids = 5 original + 493 new
  run bash -c 'python3 "$1" --all --json | python3 -c "
import json,sys; d=json.load(sys.stdin); print(d[\"sessions\"], len(d[\"rows\"]))"' _ "$SUBJ"
  [ "$output" = "498 498" ]

  # THE TIMING IS RECORDED, NOT GATED, and the distinction is deliberate. A wall-clock assertion
  # is AMBIENT — this repo has already been bitten by "lr-fleet --detach returns in <=3 s", red at
  # load 70 and green at load 32, and a future lander must not inherit that as their own red. The
  # § 5 bar of 0.30 s belongs to the W6 drill on a quiet box. Measured here (cloud VM, Linux,
  # python3 3.11, 500 rows / 498 sids): 110 / 150 / 95 ms over three runs. The bound below is 10x
  # the slowest of those, which no ambient load reaches and no algorithmic regression survives:
  # the shipped `--locate` this replaces took 35.5 s.
  local t0 t1
  t0=$(date +%s)
  cc >/dev/null || true
  cc >/dev/null || true
  cc >/dev/null || true
  t1=$(date +%s)
  [ $(( t1 - t0 )) -le 5 ]
}

@test "20 § 11 #10 agentName in a NON-preferred copy is TEAMMATE; agentName:null is NOT" {
  # TWO independent defects in the one line this amendment replaced, and they push opposite ways.
  #
  # FIRST, SCOPE. The teammate test must run over EVERY copy, not the preferred one: `agentName`
  # is written on line 3-4 and a salvage copy can be truncated above it, so reading only the
  # preferred copy misses teammates whose live transcript happens to be the short one. 07e30aeb's
  # preferred copy is the 3-record stub under the live account; the key goes in a DIFFERENT copy.
  local other="$HOME/.claude-secondary/projects/$(printf '%s' "$CWD_143039" | sed 's/[^A-Za-z0-9]/-/g')/07e30aeb-0000-4000-8000-000000000000.jsonl.handed-off"
  [ -f "$other" ]
  printf '{"type":"user","agentName":"reviewer","teamName":"wave2","uuid":"u1"}\n%s' "$(cat "$other")" \
    > "$other.new"
  mv "$other.new" "$other"
  [ "$(jrow 07e30aeb teammate)" = True ]
  run cc
  printf '%s\n' "$output" | grep -q 'TEAMMATE.*07e30aeb' || false

  # SECOND, CONTENT, and this is the direction that costs. The raw `b'"agentName"' in head` this
  # replaced answers TRUE to `"agentName":null` — so an ORDINARY live session reads lead-owned and
  # the census refuses to recover it. A false positive here is a session left blocked, silently,
  # with a reason on screen that looks authoritative. The SSOT parses the top-level field and
  # requires a non-empty string.
  printf '{"type":"user","agentName":null,"uuid":"u1"}\n{"type":"system","subtype":"bridge-session"}\n' \
    > "$other"
  [ "$(jrow 07e30aeb teammate)" = False ]

  # CONTROL: the substring rule, restored, calls that same file a teammate. This is the landed
  # defect § 11 #10 names, made executable.
  local mutant="$BATS_TEST_TMPDIR/mut-substr.py"
  python3 - "$SUBJ" "$mutant" <<'PY'
import sys
src = open(sys.argv[1]).read()
old = '    out["teammate"] = PRED.is_teammate_head(head)'
assert old in src, "anchor moved"
open(sys.argv[2], "w").write(
    src.replace(old, '    out["teammate"] = b\'"agentName"\' in head', 1))
PY
  run bash -c 'PYTHONPATH="$2" python3 "$1" --all --json | python3 -c "
import json,sys
print([r[\"teammate\"] for r in json.load(sys.stdin)[\"rows\"] if r[\"sid\"].startswith(\"07e30aeb\")][0])"' \
    _ "$mutant" "$REPO/scripts/limit-recover"
  [ "$output" = True ]                   # RED: the real subject says False

  # ...and the truncated-head class the parse arm alone would REGRESS on — 3 of 55 real teammate
  # heads run past the byte bound mid-string, because one record carries the whole of CLAUDE.md.
  printf '{"type":"user","agentName":"reviewer","teamName":"wave2","attachment":"%s\n' \
    "$(head -c 9000 /dev/zero | tr '\0' 'x')" > "$other"
  [ "$(jrow 07e30aeb teammate)" = True ]
}

@test "21 § 11 #11 an ABSENT store is a footer note at 0; one that EXISTS unreadable is exit 5" {
  # ONE RULE, and its whole content is that these two facts demand OPPOSITE actions. "Nothing has
  # ever been parked here" is a fact about the FLEET and a healthy box says it every time.
  # "I could not open the parked directory" is a fact about the BOX and must stop the census.
  # Collapsing them gives the `empty-vs-no-surface` failure: one sentence for both, and the
  # sentence is the healthy one.
  rm -rf "$LR_STATE_DIR/faults"
  local out rc=0
  out="$(cc)" || rc=$?
  [ "$rc" -eq 0 ]                                        # absent is NOT degraded and NOT broken
  printf '%s\n' "$out" | grep -q 'absent: faults/' || false
  printf '%s\n' "$out" | grep -q '07e30aeb' || false     # and the census still answers

  # EXISTS-BUT-UNREADABLE. The shape is ENOTDIR, not a permission bit, and that choice is
  # load-bearing: this suite runs as root on the cloud VM, where chmod 000 does not deny root and
  # `os.listdir` SUCCEEDS — a permission-based row would pass there while testing nothing, which
  # is `harness-default-collapses-the-states-under-test` exactly. ENOTDIR denies every uid.
  rm -rf "$LR_STATE_DIR/locks"
  : > "$LR_STATE_DIR/locks"
  rc=0
  out="$(cc 2>/dev/null)" || rc=$?
  [ "$rc" -eq 5 ]
  [ -z "$out" ]                                          # EMPTY stdout, never a partial census
  run bash -c 'python3 "$1" 2>&1 1>/dev/null' _ "$SUBJ"
  printf '%s\n' "$output" | grep -q 'locks/' || false    # stderr NAMES the store
}

@test "22 § 11 #12 through a symlink, cc-limited imports the predicate beside ITS OWN realpath" {
  # WHICH lr_predicate a converged cc-limited imports is not a detail: the live ~/.claude is a
  # per-file symlink farm over a checkout, so the binary on PATH is a link and the module beside
  # it is whatever that link resolves to. Resolving sys.path from `__file__` unresolved would make
  # a worktree's binary import the LIVE module (or die), which is the `symlinked-$0-splits-sibling-
  # sources` class. The rule is: the module ALWAYS matches the binary that is running.
  #
  # The arms differ in ONE thing — which checkout the symlink points into — so a second checkout
  # is built with a SENTINEL predicate whose is_teammate_head always answers True. If the binary
  # imported the repo's module instead, no row would be TEAMMATE and the sentinel would be
  # invisible; the assertion is on the sentinel's EFFECT, which cannot be faked by a green.
  local B="$BATS_TEST_TMPDIR/checkout-b"
  mkdir -p "$B/bin" "$B/scripts/limit-recover" "$BATS_TEST_TMPDIR/link"
  cp "$SUBJ" "$B/bin/cc-limited"
  cp "$REPO/scripts/limit-recover/lr_predicate.py" "$B/scripts/limit-recover/lr_predicate.py"
  printf '\n\ndef is_teammate_head(data):  # SENTINEL — checkout B only\n    return True\n' \
    >> "$B/scripts/limit-recover/lr_predicate.py"
  ln -s "$B/bin/cc-limited" "$BATS_TEST_TMPDIR/link/cc-limited"

  # through the symlink: checkout B's module answers, so every row is TEAMMATE
  run bash -c 'python3 "$1" --all | grep -c TEAMMATE' _ "$BATS_TEST_TMPDIR/link/cc-limited"
  [ "$output" -ge 1 ]

  # CONTROL, same fixture, same instant, different checkout: the repo's own binary is unaffected.
  # Without this arm row 22 is satisfiable by a subject that calls everything a teammate.
  run bash -c 'python3 "$1" --all | grep -c TEAMMATE || true' _ "$SUBJ"
  [ "$output" = 0 ]

  # and the module's path is under B, not under the repo — asserted directly, not inferred
  run bash -c 'cd "$2" && PYTHONPATH="$3" python3 -c "
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(sys.argv[1])), \"..\", \"scripts\", \"limit-recover\"))
import lr_predicate
print(os.path.realpath(lr_predicate.__file__).startswith(os.path.realpath(os.path.join(os.path.dirname(os.path.realpath(sys.argv[1])), \"..\"))))
" "$1"' _ "$BATS_TEST_TMPDIR/link/cc-limited" "$BATS_TEST_TMPDIR" "$B/scripts/limit-recover"
  [ "$output" = True ]
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
