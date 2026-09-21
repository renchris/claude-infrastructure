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
  #
  # THE SCREEN BUDGET CARRIES NO CORRECTION, so state WHY rather than leave it to be discovered:
  # the default screen renders BASENAMES, never stored paths, so the fixture root reaches it in
  # no spelling at all. That is asserted below, not assumed — the day a row starts printing a
  # path, this bar silently becomes a measurement of BATS_TEST_TMPDIR's depth.
  run bash -c 'python3 "$1" | wc -c' _ "$SUBJ"
  [ "$output" -le 1200 ]

  # THE BUDGET IS ABOUT PRODUCTION PATH LENGTHS, and the fixture root is a bats tmpdir that is
  # far longer than a real one AND appears inside every stored path. Left raw, this assertion
  # would measure the harness rather than the tool, and it would pass or fail depending on how
  # deep BATS_TEST_TMPDIR happens to sit. So the inflation is subtracted explicitly: each
  # occurrence of the fixture root is re-priced at the length of a real one ("/Users/chrisren").
  #
  # THE CORRECTION HAS TO COVER EVERY SPELLING, AND THIS ROW IS HERE BECAUSE IT DID NOT — the
  # post-land RED at 6a0a05f8c (a commit that touches nothing this suite reads; whole-tree
  # attribution). `tp` names a Claude Code PROJECT DIRECTORY, whose basename is the cwd with
  # every NON-ALPHANUMERIC character mapped to `-` — the subject's own `slug_of`
  # (bin/cc-limited:440) and the fixture's (build.sh:69), quoted here rather than guessed at,
  # because a narrower guess (`/` and `.` only) reads socc=0 on a tmpdir carrying `_`. So the
  # fixture root is in the JSON in TWO spellings, and a
  # `grep -o "$W"` sees only one: the four `tp` values each carried an uncounted copy, which is
  # 4 x |W| of inflation subtracted from nothing. Measured on this fixture, adj read 5880 at
  # |W|=31 and 6432 at |W|=169 — the same census, the same bytes, one side of a 6144 bar and
  # then the other. |W| ~ 78 for a hand-run `bats`, but postland-verify hands the corpus a
  # NESTED private TMPDIR (scripts/postland-verify.sh:260, `$TMPDIR/postland-run.XXXXXX`),
  # which is what pushes it past ~97 and is why this red never reproduced standalone.
  local raw occ slug socc tot adj tok leaked
  cc --json > "$BATS_TEST_TMPDIR/shape.json"
  raw="$(wc -c < "$BATS_TEST_TMPDIR/shape.json" | tr -d ' ')"
  slug="$(printf '%s' "$W" | sed 's/[^A-Za-z0-9]/-/g')"
  # -F, because $W is a PATH being handed to a tool that reads a REGEX: a `.` in the tmpdir is
  # `any character` to BRE, and the one thing a correction may never do is over-count itself.
  occ="$(grep -oF -- "$W"    < "$BATS_TEST_TMPDIR/shape.json" | wc -l | tr -d ' ')"
  socc="$(grep -oF -- "$slug" < "$BATS_TEST_TMPDIR/shape.json" | wc -l | tr -d ' ')"
  tot=$(( occ + socc ))
  # |slug| == |W| by construction (the substitution is 1:1), and 15 is the same production
  # re-pricing both spellings get: "/Users/chrisren" and "-Users-chrisren" are the same length.
  adj=$(( raw - tot * ${#W} + tot * 15 ))
  [ "$occ"  -gt 0 ]                      # the correction is real, not a no-op
  [ "$socc" -gt 0 ]                      # …and the slug spelling is PRESENT, not hypothetical

  # …and the promise made at the 1200 B bar, now that both spellings are in hand.
  cc > "$BATS_TEST_TMPDIR/shape.screen"
  [ "$(grep -cF -- "$W"    "$BATS_TEST_TMPDIR/shape.screen" || true)" = 0 ]
  [ "$(grep -cF -- "$slug" "$BATS_TEST_TMPDIR/shape.screen" || true)" = 0 ]

  # INVARIANCE, ASSERTED RATHER THAN HOPED FOR — the durable half of this fix. Strip both
  # spellings and nothing derived from the fixture root may survive: the run tmpdir's own random
  # token (`bats-run-XXXXXX`) is alphanumerics and dashes, both of which slug_of maps to
  # themselves, so it reads identically in EVERY spelling of a path that contains it — which is
  # what makes it a detector rather than a fourth guess. A non-zero count means a THIRD spelling
  # is inflating `raw` uncorrected and this budget has quietly gone back to being a fact about
  # the harness.
  tok="$(basename "$BATS_RUN_TMPDIR")"
  [ -n "$tok" ]
  [ "$(grep -oF -- "$tok" < "$BATS_TEST_TMPDIR/shape.json" | wc -l | tr -d ' ')" -gt 0 ]
  # THE HEREDOC IS NOT INSIDE A `$( … )`, and that is deliberate rather than a style choice:
  # /bin/bash on the desk is 3.2, and 3.2 scans for the `)` that closes a command substitution
  # across the RAW TEXT of the body INCLUDING a heredoc it never executes. A `(` inside this
  # program would then be counted, and the file reports `unexpected EOF` hundreds of lines away.
  # Written to a file first, the heredoc is at statement level and nothing is counting.
  cat > "$BATS_TEST_TMPDIR/leak.py" <<'PY'
import sys
d = open(sys.argv[1], encoding="utf-8").read()
for spelling in (sys.argv[2], sys.argv[3]):
    d = d.replace(spelling, "")
print(d.count(sys.argv[4]))
PY
  leaked="$(python3 "$BATS_TEST_TMPDIR/leak.py" "$BATS_TEST_TMPDIR/shape.json" "$W" "$slug" "$tok")"
  [ "$leaked" -eq 0 ]

  echo "# --json ${raw} B raw · ${tot} fixture-root occurrences (${occ} literal, ${socc} slug)" \
       "at |W|=${#W} · ${adj} B re-priced (budget 6144)" >&3
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

# ── 16-22: the § 11 amendments ───────────────────────────────────────────────────────────────────
# Seven rows, one per amendment that names a W2b row: #2 #3 #4 #7 #10 #11 #12. Each amendment is a
# critic gap closed against the synthesis, so each row here is the executable form of a decision
# that would otherwise live only in a table.

@test "16 a beat with a live pid and NO registry row is RECOVERABLE, not NO-PANE" {
  # § 11 #2. P5 REFUTED the registry's completeness: 3 of 14 rate_limit sids had no row at all,
  # and the cause is pane-keyed OVERWRITE — the row is written and then replaced by the pane's
  # next occupant. `cc-beats/<sid>.json` is sid-keyed and survives that, carrying the same
  # (pid,lstart) pin. A census single-sourced on the registry calls this session dead and stops
  # offering the one recovery that would work: nudging the pane it is still sitting in.
  printf '{"ts":"2026-09-19T20:35:00Z","error":"rate_limit","config_dir":"%s","session_id":"beaa7e00-0000-4000-8000-000000000000","cwd":"%s","pane":"","transcript_path":"","last_assistant_message":"You'"'"'ve hit your session limit"}\n' \
    "$W/home/.claude-tertiary" "$CWD_INFRA" >> "$M/rate_limit__next3.jsonl"
  printf '{"sid":"beaa7e00-0000-4000-8000-000000000000","pane":"203","pid":55555,"lstart":"Fri Sep 19 12:00:00 2026"}\n' \
    > "$CC_LIMITED_BEATS/beaa7e00-0000-4000-8000-000000000000.json"
  echo "55555 Fri Sep 19 12:00:00 2026" >> "$CC_LIMITED_PS"
  [ "$(jrow beaa7e00 state)" = RECOVERABLE ]
  run cc
  # the beat is also the only store that still names the pane, so it renders rather than blanking
  printf '%s\n' "$output" | grep -q 'RECOVERABLE .*#203  beaa7e00' || false

  # CONTROL (the amendment names it): the SAME beat with a DEAD pid must be NO-PANE. Without this
  # the row above is satisfiable by a census that treats the mere EXISTENCE of a beat as life,
  # which would resurrect every session that ever submitted a prompt.
  grep -v '^55555 ' "$CC_LIMITED_PS" > "$CC_LIMITED_PS.new"
  mv "$CC_LIMITED_PS.new" "$CC_LIMITED_PS"
  [ "$(jrow beaa7e00 state)" = NO-PANE ]
}

@test "17 a parked-only sid — no marker row anywhere — is surfaced with its cap and its reset" {
  # § 11 #3. The marker writer has six paths that write NOTHING and exit 0, so `parked/` is
  # sometimes the ONLY evidence a session is blocked. Its fields are its own (parked_at, cfg,
  # reset_at_utc, kind) and it carries no assistant text at all — so it must classify BY CAP.
  # Classifying "" by TEXT returns `other`, the one verdict that means "never parked", and the
  # census would then contradict the very poller that parked it.
  printf '{"sid":"7a2ked00-0000-4000-8000-000000000000","acct":"next3","cfg":"%s","cwd":"%s","kind":"weekly","reset_at_utc":"2026-09-19T23:00:00Z","parked_at":"2026-09-19T21:05:00Z"}\n' \
    "$W/home/.claude-tertiary" "$CWD_INFRA" > "$LR_STATE_DIR/parked/7a2ked00-0000-4000-8000-000000000000.json"
  [ "$(jrow 7a2ked00 cap)" = seven_day ]
  [ "$(jrow 7a2ked00 recoverable_by_waiting)" = True ]
  [ "$(jrow 7a2ked00 group)" = next3 ]
  run cc
  printf '%s\n' "$output" | grep -q '7a2ked00' || false
  printf '%s\n' "$output" | grep -q 'seven_day · resets 23:00:00Z' || false

  # A 'fable' park is the same path and the opposite waitability — the cap map is the whole
  # classification, so the row above must not be satisfiable by hard-coding one kind.
  printf '{"sid":"fab1e000-0000-4000-8000-000000000000","acct":"next3","cfg":"%s","cwd":"%s","kind":"fable","reset_at_utc":"","parked_at":"2026-09-19T21:06:00Z"}\n' \
    "$W/home/.claude-tertiary" "$CWD_INFRA" > "$LR_STATE_DIR/parked/fab1e000-0000-4000-8000-000000000000.json"
  [ "$(jrow fab1e000 cap)" = "model_scoped:Fable" ]
  [ "$(jrow fab1e000 recoverable_by_waiting)" = False ]
}

@test "18 one file reachable under two roots is ONE copy — the dedupe counts inodes" {
  # § 11 #4. The dedupe read `realpath(root)` on the belief that ~/.claude-next IS a symlink to
  # ~/.claude. It is not: ~/.claude-next is a REAL directory and only its `projects/` is the link.
  # So the key never collided, the dedupe was inert, and every `next` transcript was enumerated
  # once per root — one session reporting a salvage history it does not have.
  #
  # build.sh creates no ~/.claude-next at all, so this builds the real production shape from
  # scratch: a REAL directory whose `projects/` ALONE is a link into ~/.claude/projects.
  mkdir -p "$W/home/.claude/projects" "$W/home/.claude-next"
  ln -s "$W/home/.claude/projects" "$W/home/.claude-next/projects"
  local slug; slug="$(printf '%s' "$CWD_INFRA" | sed 's/[^A-Za-z0-9]/-/g')"
  mkdir -p "$W/home/.claude/projects/$slug"
  printf '{"type":"system","subtype":"bridge-session"}\n' \
    > "$W/home/.claude/projects/$slug/dedu9000-0000-4000-8000-000000000000.jsonl"
  printf '{"ts":"2026-09-19T20:36:00Z","error":"rate_limit","config_dir":"%s","session_id":"dedu9000-0000-4000-8000-000000000000","cwd":"%s","pane":"","transcript_path":"","last_assistant_message":"You'"'"'ve hit your session limit"}\n' \
    "$W/home/.claude-next" "$CWD_INFRA" >> "$M/rate_limit__next3.jsonl"
  # BOTH roots are enumerated, and they reach the same inode by two different paths.
  export CC_LIMITED_ROOTS="$W/home/.claude:$W/home/.claude-next:$W/home/.claude-secondary:$W/home/.claude-tertiary"
  [ "$(jrow dedu9000 copies)" = 1 ]
  # the correction is REAL, not a no-op: the same file is genuinely visible under both spellings.
  run bash -c 'ls "$1/.claude/projects/$2/" "$1/.claude-next/projects/$2/" | grep -c dedu9000' _ "$W/home" "$slug"
  [ "$output" = 2 ]
}

@test "19 a 500-row marker file x3 still renders inside the 0.30 s budget" {
  # § 11 #7. D3 was amended to TTL 10080 / CAP 500 rather than the proposed CAP 5000, on the
  # ground that per-sid grouping already dedupes at read. That is only true if the READ itself
  # stays inside the hook's own budget AT the cap, so the cap is pinned by a measurement here
  # rather than by the argument that motivated it.
  python3 - "$M" "$W/home/.claude-tertiary" "$CWD_INFRA" <<'PY'
import json, sys
M, CFG, CWD = sys.argv[1], sys.argv[2], sys.argv[3]
for f in ("bulk_a", "bulk_b", "bulk_c"):
    with open("%s/rate_limit__%s.jsonl" % (M, f), "w") as fh:
        for i in range(500):
            fh.write(json.dumps({
                "ts": "2026-09-19T2%d:%02d:%02dZ" % (i % 2, i % 60, i % 60),
                "error": "rate_limit", "config_dir": CFG, "cwd": CWD, "pane": "",
                "session_id": "%s%04d-0000-4000-8000-000000000000" % (f[-1] * 4, i),
                "transcript_path": "",
                "last_assistant_message": "You've hit your session limit"}) + "\n")
PY
  run cc --all
  [ "$status" -eq 0 ]
  # THE INSTRUMENT MEASURES THE CENSUS, NOT THE HARNESS, AND NOT THE BOX.
  #
  # Two corrections, the second found by this row going red on trunk. (1) Bracketing a bats `run`
  # with two `python3 -c` clock reads charges the subject ~110 ms of interpreter startup it never
  # spent — 260 ms measured for a 140 ms census. So it is ONE fork, timed inside the timer's own
  # process. (2) WALL CLOCK ON A SHARED BOX IS A FACT ABOUT THE BOX. This suite runs beside up to
  # three other bats roots; measured at load 84 on 10 cores, the same census read 479 ms against
  # its 300 ms bar while a direct run of it took 141. A timing assertion that a sibling's load can
  # flip is not a budget, it is a flake that reddens trunk for whoever lands next.
  #
  # So the ASSERTION is child CPU (user+sys), which contention does not inflate — 130-146 ms
  # across every load this box has shown. The WALL arm is kept, because the hook's budget really
  # is wall clock from the operator's side, but it SKIPS rather than reds when the box is too
  # loaded for the number to mean anything: an environment-falsifiable precondition must skip.
  local ms cpu load percore
  read -r ms cpu <<<"$(python3 -c '
import resource, subprocess, sys, time
b = resource.getrusage(resource.RUSAGE_CHILDREN)
t = time.time()
subprocess.run([sys.executable, sys.argv[1], "--all"], stdout=subprocess.DEVNULL)
a = resource.getrusage(resource.RUSAGE_CHILDREN)
cpu = (a.ru_utime - b.ru_utime) + (a.ru_stime - b.ru_stime)
print(int((time.time() - t) * 1000), int(cpu * 1000))' "$SUBJ")"
  load="$(uptime | sed 's/.*averages*: *//' | awk '{print $1}' | tr -d ,)"
  percore="$(python3 -c "import os,sys;print(float(sys.argv[1])/(os.cpu_count() or 1))" "$load")"
  echo "# 1500 marker rows (3 files at the 500-row cap): cpu ${cpu} ms · wall ${ms} ms" \
       "(budget 300) · load/core ${percore}" >&3
  # THE LOAD-INVARIANT BAR, always asserted.
  [ "$cpu" -le 300 ]
  # THE WALL BAR, only where wall clock is measurable. 2.0/core is the ceiling cc-bats itself
  # uses to decide the box cannot give a trustworthy answer, so it is the same line here.
  if [ "$(python3 -c "print(1 if float('$percore') >= 2.0 else 0)")" = 1 ]; then
    skip "load/core ${percore} >= 2.0 — wall clock here measures the box, not the census (cpu was ${cpu} ms)"
  fi
  [ "$ms" -le 300 ]
}

@test "20 TEAMMATE is decided by the SSOT predicate, and by EVERY copy — not by a substring" {
  # § 11 #10. Two halves, and only the second can go red against the shipped subject.
  # (a) EQUIVALENCE GUARD: the key lands on line 3-4 and a salvage copy can be truncated above
  #     it, so the test must run over every copy, not only the preferred one. The shipped code
  #     already ORs across scans — this half GUARDS that rule rather than proving it, and is
  #     recorded as such in the RED-PROOF footer instead of being claimed as a red.
  # setup() exports CWD_INFRA only; this row needs the 143039 worktree, spelled as build.sh does.
  local slug; slug="$(printf '%s' "$W/Users/chrisren/Development/.worktrees/wt-cc-143039-68221" \
    | sed 's/[^A-Za-z0-9]/-/g')"
  printf '{"type":"user","agentName":"reviewer","teamName":"w2b"}\n' \
    >> "$W/home/.claude-secondary/projects/$slug/07e30aeb-0000-4000-8000-000000000000.jsonl.handed-off"
  [ "$(jrow 07e30aeb teammate)" = True ]
  [ "$(jrow 07e30aeb state)" = TEAMMATE ]

  # (b) THE RED HALF: a raw `"agentName" in head` answers TRUE to a NULL value and to a record
  #     merely quoting the field name inside a text payload. TEAMMATE is the FIRST arm of the
  #     state table, so a false positive is a session the census refuses to recover forever and
  #     never mentions again. The SSOT requires a parsed TOP-LEVEL key with a NON-EMPTY string.
  printf '{"type":"system","subtype":"queue-operation","op":"enqueue"}\n{"type":"user","agentName":null}\n{"type":"assistant","message":{"content":[{"type":"text","text":"the \\"agentName\\" field"}]}}\n' \
    > "$W/home/.claude-tertiary/projects/$slug/07e30aeb-0000-4000-8000-000000000000.jsonl"
  rm -f "$W/home/.claude-secondary/projects/$slug/07e30aeb-0000-4000-8000-000000000000.jsonl.handed-off"
  [ "$(jrow 07e30aeb teammate)" = False ]
}

@test "21 an ABSENT optional store is an empty at exit 0; one it CANNOT READ is exit 5" {
  # § 11 #11, the ONE disposition rule. `os.listdir` raises the same way for ENOENT and EACCES,
  # so both arrived as the same empty list: a `locks/` the census could not read rendered as a
  # census in which nobody had claimed anything, and every FAULT CLAIMED-NOT-LIVE row vanished
  # silently. That is the false-calm shape this tool exists to end, wearing a different hat.
  rmdir "$LR_STATE_DIR/faults"
  run cc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'absent (read as empty): faults' || false
  printf '%s\n' "$output" | grep -q '98f02458' || false          # rows still rendered
  # the claim rows the locks dir feeds are present, so the arm below is a REAL loss of content
  printf '%s\n' "$output" | grep -q 'FAULT CLAIMED-NOT-LIVE' || false

  local out rc=0

  # ARM 1 — ENOTDIR, and it is the arm that runs EVERYWHERE. A regular file where the store's
  # directory belongs is `exists() == True` + `listdir()` raises, which is precisely the state the
  # rule above is about, reached through the same `probe_source` line as EACCES. It is used as the
  # unconditional arm because no uid can bypass ENOTDIR, where EACCES has a privilege precondition
  # (arm 2). Measured 2026-09-21: `NotADirectoryError` errno 20 raises for uid 0.
  mv "$LR_STATE_DIR/locks" "$LR_STATE_DIR/locks.d"
  : > "$LR_STATE_DIR/locks"
  rc=0; out="$(cc 2>/dev/null)" || rc=$?
  [ "$rc" -eq 5 ]
  [ -z "$out" ]
  # …and stderr NAMES the store, so the operator is not left to guess which one went down
  run bash -c 'python3 "$1" 2>&1 1>/dev/null' _ "$SUBJ"
  printf '%s\n' "$output" | grep -q 'locks' || false
  rm -f "$LR_STATE_DIR/locks"
  mv "$LR_STATE_DIR/locks.d" "$LR_STATE_DIR/locks"

  # ARM 2 — EACCES, THE ORIGINAL, AND IT IS SKIPPED ONLY WHERE IT CANNOT FAIL. root holds
  # CAP_DAC_OVERRIDE, so `chmod 000` denies it nothing: `listdir` SUCCEEDS, the census exits 0, and
  # this arm goes red having tested the uid rather than the subject. That red is not free — it
  # convicts the diff of whoever is landing, and this repo now lands from cloud VMs that run as
  # root (measured 2026-09-21: uid 0 ⇒ `not ok 23`, uid 1001 ⇒ `ok`, one variable). The skip is
  # therefore a PRECONDITION, not a quarantine: arm 1 above holds the same rule unconditionally, so
  # no coverage of § 11 #11 is lost where this is skipped — only the EACCES spelling of it.
  if [ "$(id -u)" -eq 0 ]; then
    skip "EACCES arm needs an unprivileged uid; root bypasses DAC. Arm 1 (ENOTDIR) covered the rule."
  fi
  rc=0
  chmod 000 "$LR_STATE_DIR/locks"
  out="$(cc 2>/dev/null)" || rc=$?
  chmod 755 "$LR_STATE_DIR/locks"
  [ "$rc" -eq 5 ]
  [ -z "$out" ]
  run bash -c 'chmod 000 "$2/locks"; python3 "$1" 2>&1 1>/dev/null; chmod 755 "$2/locks"' _ "$SUBJ" "$LR_STATE_DIR"
  printf '%s\n' "$output" | grep -q 'locks' || false
}

@test "22 through a SYMLINK, the predicate imported is the one beside the binary that ran" {
  # § 11 #12. `~/.claude/bin/cc-limited` is a per-file symlink into a checkout, and this fleet has
  # several checkouts of this repo live at once. If sys.path were built from `__file__` the
  # worktree's binary would import the LIVE checkout's predicate — a landed classification change
  # would test green in its own worktree and run the old rule everywhere, with no diff to show
  # for it. `os.path.realpath` pins the module to the binary that is actually executing.
  local link="$BATS_TEST_TMPDIR/bin/cc-limited"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  ln -sf "$SUBJ" "$link"
  # the link is genuinely a link, into a DIFFERENT directory, or the row proves nothing
  [ -L "$link" ]
  [ "$(dirname "$link")" != "$(dirname "$SUBJ")" ]
  # and it runs through the link WITHOUT a PYTHONPATH — which is the assertion: the import
  # resolved, so the module was found relative to the REAL path, not the link's directory.
  run env -u PYTHONPATH python3 "$link" --json
  [ "$status" -eq 0 ]
  # the module it resolves is the one under the same checkout as realpath(cc-limited)
  run bash -c 'env -u PYTHONPATH python3 - "$1" <<'"'"'PY'"'"'
import os, sys
link = sys.argv[1]
real = os.path.realpath(link)
sys.path.insert(0, os.path.join(os.path.dirname(real), "..", "scripts", "limit-recover"))
import lr_predicate
want = os.path.join(os.path.dirname(os.path.dirname(real)), "scripts", "limit-recover")
print(os.path.realpath(os.path.dirname(lr_predicate.__file__)) == os.path.realpath(want))
PY' _ "$link"
  [ "$output" = True ]

  # THE MUTANT, because this row is GREEN IN BOTH ARMS. § 11 #12 was already satisfied on HEAD
  # (`sys.path` has been built from realpath since :68 shipped), so there is no fix here to go
  # red against — which makes this an equivalence guard, and an equivalence guard is worth
  # nothing until the mutation it guards against is built and killed. Drop the `realpath` and
  # the import resolves against the LINK's directory, where no `scripts/limit-recover` exists.
  local mutant="$BATS_TEST_TMPDIR/mut-file.py"
  sed 's|os.path.dirname(os.path.realpath(__file__))|os.path.dirname(__file__)|' "$SUBJ" > "$mutant"
  grep -q 'os.path.dirname(__file__)' "$mutant"        # the mutation actually applied
  local mlink="$BATS_TEST_TMPDIR/bin/mut-cc-limited"
  ln -sf "$mutant" "$mlink"
  local rc=0
  env -u PYTHONPATH python3 "$mlink" --json >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 5 ]                                      # RED: it cannot find its own predicate
}

# ── RED-PROOF: rows 16-22 against PRISTINE HEAD (d4a47bd9c) ──────────────────────────────────────
# Each row below was run once with `git checkout d4a47bd9c -- bin/cc-limited` in place and the
# CURRENT fixture, so the only variable is the subject. Six went red; the seventh did not, and it
# is recorded as what it is rather than as a red that was never observed.
#
#   not ok 18  16 a beat with a live pid and NO registry row is RECOVERABLE, not NO-PANE
#              `[ "$(jrow beaa7e00 state)" = RECOVERABLE ]' failed      (§ 11 #2 unimplemented:
#              `cc-beats` returns 0 hits in bin/cc-limited on HEAD — liveness was registry-only)
#   not ok 19  17 a parked-only sid … is surfaced with its cap and its reset
#              `[ "$(jrow 7a2ked00 cap)" = seven_day ]' failed          (§ 11 #3: parked_sids()
#              enumerated a store nothing consumed; the sid never became a row at all)
#   not ok 20  18 one file reachable under two roots is ONE copy
#              `[ "$(jrow dedu9000 copies)" = 1 ]' failed               (§ 11 #4: read 2 — the
#              dedupe was keyed on realpath(root), which never collides)
#   not ok 21  19 a 500-row marker file x3 … inside the 0.30 s budget
#              cpu 438 ms against the 300 ms bar                        (§ 11 #7: the slug-miss
#              full walk was paid per sid — 19,532 listdir calls). RE-PROVED against pristine
#              AFTER this row was made load-invariant, at load/core 6.5, where the fixed subject
#              reads 164 ms: a 2.7x effect the box cannot manufacture. The original proof was a
#              WALL number (359 ms) and it was the weaker one — see the row's own comment for why
#              a wall assertion on this box reddened trunk at load 84 for a 141 ms census.
#   not ok 22  20 TEAMMATE is decided by the SSOT predicate
#              `[ "$(jrow 07e30aeb teammate)" = False ]' failed         (§ 11 #10: the raw
#              substring answers TRUE to `"agentName":null`. NOTE the red is on the row's SECOND
#              assertion; its first — apply the test to EVERY copy — passed pre-fix and is an
#              equivalence guard, labelled as such in the row itself.)
#   not ok 23  21 an ABSENT optional store is an empty at exit 0; one it CANNOT READ is exit 5
#              the `absent (read as empty): faults` footer was missing  (§ 11 #11: listdir raises
#              alike for ENOENT and EACCES, so both arrived as the same empty list)
#   ---- ok 24 22 through a SYMLINK, the predicate imported is the one beside the binary that ran
#              GREEN IN BOTH ARMS — NOT a red proof. § 11 #12 was already satisfied on HEAD
#              (bin/cc-limited:68 has built sys.path from os.path.realpath(__file__) since it
#              shipped), so there is no fix for this row to go red against. It is an EQUIVALENCE
#              GUARD, and it is worth nothing on that evidence alone — so the row carries the
#              mutation it guards against and kills it: dropping the `realpath` makes the import
#              resolve against the LINK's directory and the subject exits 5. That mutant, not a
#              pre-fix red, is this row's proof of power.
#
# THE FIXTURE'S OWN PROVENANCE, since three of these rows turn on it: tests/fixtures/lr-2026-09-19/
# CAPTURE-RECEIPT.md records a live capture and derives § 5's row-1 state from it rather than
# quoting the plan. Its finding: 07e30aeb has no registry row anywhere, no resume leaf, and a beat
# whose pid is dead — so row 1's true state is NO-PANE, and the `#147 RECOVERABLE (stub)` the drill
# asserted described one moment. build.sh still builds a world where that pid is alive, which is a
# legitimate designed fixture; what it no longer does is call that registry row measured.

# ── MEASUREMENTS AND THE MUTANT BATTERY ──────────────────────────────────────────────────────────
# WALL CLOCK, three runs over the 5-session fixture on the cloud VM (Linux, python3 3.11):
#   0.038 0.037 0.038 s.  Budget 0.30 s; the shipped `lr-fleet.sh --locate` it replaces measured 35.5 s.
# That is roughly three orders of magnitude, and it is the whole point rather than a nicety: the
# old census's window was longer than the fleet's own state-change interval, so it described a
# world that had never existed at any instant.
#
# SIZE, same fixture: default screen 896 B (budget 1,200), --json 5,816 B re-priced (budget 6,144).
#
# AND THE ONLY NUMBER IN THIS FILE THAT IS WORTH MORE THAN ITS VALUE — that 5,816 is now
# INVARIANT, measured by running row 15 under three deliberately different harness depths:
#
#   |W| = 31   raw 6,168 B   -> re-priced 5,816     (TMPDIR=/tmp)
#   |W| = 139  raw 8,544 B   -> re-priced 5,816
#   |W| = 169  raw 9,204 B   -> re-priced 5,816
#
# The PREVIOUS correction read 5,880 / 6,336 / 6,432 over the same three — the same census, the
# same bytes, one side of the 6,144 bar and then the other. It subtracted the literal fixture root
# and not its `slug_of` transliteration, which `tp` carries once per row. That is the post-land RED
# at 6a0a05f8c, and it is invisible to a hand-run `bats` (|W| ~ 78) because the breach needs
# |W| >= ~97 — which is what postland-verify's NESTED private TMPDIR supplies. Row 15 now asserts
# the invariance instead of relying on it, and that guard has power: strip one spelling instead of
# two and `[ "$leaked" -eq 0 ]` fails.
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
#
# ── RED-PROOF: row 21's ENOTDIR arm (added 2026-09-21, off-box verification of LIMIT_DETECT_100P) ─
#
# Row 21 asserted § 11 #11's "exists but cannot be read" through `chmod 000` ALONE. That spelling
# has an unstated precondition — an unprivileged uid — and it convicts the wrong party when it is
# unmet: root holds CAP_DAC_OVERRIDE, so `listdir` succeeds, the census exits 0, and the row goes
# red having measured the UID rather than the subject. Measured both arms, one variable:
#
#   uid 0    (cloud VM, this repo now lands from one)  ->  not ok 23 … `[ "$rc" -eq 5 ]' failed
#   uid 1001 (ccprobe, same box, same tree, same bats) ->  ok 23
#
# The cure is an arm no uid can bypass, reaching the SAME `probe_source` line: a regular file where
# the store's directory belongs is `exists() == True` + `listdir()` raising NotADirectoryError
# (errno 20, confirmed raising for uid 0). It runs unconditionally; the EACCES arm is kept and now
# states its precondition with `skip`, so the rule keeps full coverage on the desk and does not
# fabricate a red anywhere else.
#
# IT CONVICTS — the arm is not decorative. M6, run as ROOT so ONLY the new arm was live:
#
#   M6  probe_source returns False instead of raising Unreadable   -> 21
#       (i.e. the pre-§ 11 #11 defect itself: the swallow that made an unreadable locks/ render as
#        a fleet in which nobody had claimed anything)
#       vs mutant: `not ok 1 21 …` at `[ "$rc" -eq 5 ]`;  vs pristine: `ok 1 21`.
