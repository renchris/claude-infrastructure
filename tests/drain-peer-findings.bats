#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2329
#   Structurally false under bats: every @test body IS its own subshell, so an `export` inside one
#   is *meant* to be test-local (SC2030/SC2031), and setup()'s helpers run from those subshells.
#
# W3-B4 — the harvest instrument's corrected filter, and the peer-findings drain producer.
#
# WHAT THIS SUITE GUARDS, AND WHY EACH CASE IS A RED-PROOF RATHER THAN AN EQUIVALENCE GUARD.
#
# Part 1 (the instrument). W2-B4 measured "does a finding a close NAMES ever reach a store" and
# reported its own defect: the document-frequency filter screened tokens against the CLOSES while
# the inflation comes from the HAYSTACK, so `claude`, `MEMORY.md`, `slop-lint.sh` and friends
# scored 13 of 20 hand-read pairs as harvested on evidence about a DIFFERENT piece of work. The
# control arm here is the PRISTINE PRE-FIX ARTIFACT read straight out of git by BLOB id
# (550373d55c3c9dbcc44baa077979cf97ce20314e) — never a hand-edited approximation, and never
# `HEAD`, which stops being pre-fix the moment this branch lands. A blob id is content-addressed,
# so a rebase that rewrites the commit sha leaves it reachable (memory:
# cited-sha-may-not-survive-the-land).
#   · case 1 is the DISCRIMINATOR: one fixture, two closes, and the two arms disagree.
#   · case 2 is its POSITIVE CONTROL: a token that is genuinely distinctive must still be
#     harvested by BOTH arms, or the "fix" is just a blanket suppressor and the disagreement in
#     case 1 would mean nothing.
#
# Part 2 (the producer). drain-peer-findings.py is new code, so there is no pre-fix artifact to
# replay. Every behavioural case is therefore paired with a MUTANT — a copied tree with one line
# changed — and the test asserts the mutant DYING on the same fixture the real script passes.
# The three mutants are the three obvious wrong builds the measurement's constraints forbid:
#   M1  harvest evidence used as a FILING GATE (constraint 1: the matcher's errors are all false
#       POSITIVE harvests, so a producer that trusts it to say "already harvested" skips real
#       losses at exactly the rate the instrument is wrong)
#   M2  no settled-close guard (a close asserting closure drains a row about nothing)
#   M3  no empty-ledger guard (`follow-on: none filed.` drains as if it named work)
#
# HERMETIC BY CONSTRUCTION. HOME, the git corpus and CC_BACKLOG_FILE all point into
# $BATS_TEST_TMPDIR. Nothing here reads or writes the operator's ~/.claude/autonomy, the four
# transcript roots, or any real repository.

setup() {
  REPO="${BATS_TEST_DIRNAME}/.."
  SUT="${REPO}/scripts/drain-peer-findings.py"
  INSTRUMENT="${REPO}/scripts/measure-harvest-latency.py"
  # The pre-fix instrument, by content-addressed blob id. If this ever fails to resolve the suite
  # must go RED rather than silently comparing the fixed file against itself.
  PREFIX_BLOB="550373d55c3c9dbcc44baa077979cf97ce20314e"

  # Fixture $HOME for the WHOLE suite, not just per-invocation: every python load below
  # (mutants, selftests, the module imports) would otherwise resolve ~/ against the operator's
  # live config, and measure-harvest-latency.py reads ~/.claude/autonomy/backlog.jsonl by
  # default. Nothing in this file may touch the real store.
  export HOME="${BATS_TEST_TMPDIR}/home"
  FAKE="$HOME"
  mkdir -p "$FAKE/.claude/projects/proj"
  REPO_FIX="${BATS_TEST_TMPDIR}/fixrepo"
  LEDGER="${BATS_TEST_TMPDIR}/backlog.jsonl"
}

# ── fixture builders ─────────────────────────────────────────────────────────

# A transcript whose LAST turn-final close is $2, with cwd $3. EOF follows the assistant
# record, which is what makes it turn-final for measure-closes.extract_closes.
mk_transcript() {
  local sid="$1" text="$2" cwd="$3" ts="$4"
  python3 - "$FAKE/.claude/projects/proj/${sid}.jsonl" "$text" "$cwd" "$ts" <<'PY'
import json, sys
path, text, cwd, ts = sys.argv[1:5]
recs = [
  {"type": "user", "cwd": cwd, "timestamp": ts,
   "message": {"role": "user", "content": "go"}},
  {"type": "assistant", "cwd": cwd, "timestamp": ts,
   "message": {"id": "msg_1", "role": "assistant",
               "content": [{"type": "text", "text": text}]}},
]
with open(path, "w") as f:
    for r in recs:
        f.write(json.dumps(r) + "\n")
PY
}

git_commit_at() {   # $1 = days ago, $2 = message
  local ago="$1" msg="$2"
  local when; when="$(python3 -c "import time,sys;print(int(time.time()-float(sys.argv[1])*86400))" "$ago")"
  ( cd "$REPO_FIX" && echo "$RANDOM$msg" >> log.txt && git add -A \
    && GIT_AUTHOR_DATE="@$when +0000" GIT_COMMITTER_DATE="@$when +0000" \
       git -c user.name=t -c user.email=t@t commit -q -m "$msg" )
}

mk_git_fixture() {
  mkdir -p "$REPO_FIX"
  ( cd "$REPO_FIX" && git init -q -b main . )
  # BACKGROUND vocabulary: present BEFORE the close (t0 = 4 d ago) and again after it.
  git_commit_at 9 "chore: tidy preflight-cache.sh"
  git_commit_at 6 "fix: preflight-cache.sh retries"
  git_commit_at 2 "feat: preflight-cache.sh and offbox-core-cure land together"
}

# ── PART 1: the instrument, against the pristine pre-fix blob ────────────────

@test "the pre-fix blob resolves — a control that cannot be read is not a control" {
  run git -C "$REPO" cat-file -e "$PREFIX_BLOB"
  [ "$status" -eq 0 ]
  run bash -c "git -C '$REPO' cat-file -p '$PREFIX_BLOB' | grep -c background_df"
  [ "$output" = "0" ]                      # the pristine arm cannot express the fix
  run grep -c "def background_df" "$INSTRUMENT"
  [ "$output" = "1" ]                      # the fixed arm can
}

@test "RED-PROOF: a token that is background vocabulary counts as harvested pre-fix and does not post-fix" {
  mk_git_fixture
  local t0; t0="$(python3 -c "import time,datetime;print(datetime.datetime.utcfromtimestamp(time.time()-4*86400).strftime('%Y-%m-%dT%H:%M:%SZ'))")"
  mk_transcript "aaaaaaaa-0000-0000-0000-000000000001" \
    "🔧 Loose ends — the remaining work is in \`preflight-cache.sh\` and it is not yet done." \
    "$REPO_FIX" "$t0"

  git -C "$REPO" cat-file -p "$PREFIX_BLOB" > "${BATS_TEST_TMPDIR}/prefix.py"
  cp "${REPO}/scripts/measure-closes.py" "${BATS_TEST_TMPDIR}/measure-closes.py"

  # --df-max 1.0 disables the CLOSE-frequency filter in both arms, so the only variable is the
  # background filter under test. With 1 close a 5% cutoff would drop every token in both arms
  # and the comparison would be vacuous.
  run env HOME="$FAKE" python3 "${BATS_TEST_TMPDIR}/prefix.py" --days 14 --df-max 1.0
  [ "$status" -eq 0 ]
  echo "PRE-FIX: $output"
  [[ "$output" == *"harvested by a LATER reader (>=0.5 d): 1 / 1 = 100.0%"* ]] || false

  run env HOME="$FAKE" python3 "$INSTRUMENT" --days 14 --df-max 1.0
  [ "$status" -eq 0 ]
  echo "POST-FIX: $output"
  [[ "$output" == *"the measured population): 0"* ]] || false
  [[ "$output" == *"dropped 1 more with no token surviving the BACKGROUND filter"* ]]
}

@test "POSITIVE CONTROL: a genuinely distinctive token is still harvested by BOTH arms" {
  mk_git_fixture
  local t0; t0="$(python3 -c "import time,datetime;print(datetime.datetime.utcfromtimestamp(time.time()-4*86400).strftime('%Y-%m-%dT%H:%M:%SZ'))")"
  mk_transcript "aaaaaaaa-0000-0000-0000-000000000002" \
    "🔧 Loose ends — \`offbox-core-cure\` still remains unbuilt and is not yet done." \
    "$REPO_FIX" "$t0"

  git -C "$REPO" cat-file -p "$PREFIX_BLOB" > "${BATS_TEST_TMPDIR}/prefix.py"
  cp "${REPO}/scripts/measure-closes.py" "${BATS_TEST_TMPDIR}/measure-closes.py"

  run env HOME="$FAKE" python3 "${BATS_TEST_TMPDIR}/prefix.py" --days 14 --df-max 1.0
  [ "$status" -eq 0 ]
  [[ "$output" == *"harvested by a LATER reader (>=0.5 d): 1 / 1 = 100.0%"* ]] || false

  run env HOME="$FAKE" python3 "$INSTRUMENT" --days 14 --df-max 1.0
  [ "$status" -eq 0 ]
  echo "POST-FIX: $output"
  [[ "$output" == *"the measured population): 1"* ]] || false
  [[ "$output" == *"harvested by a LATER reader (>=0.5 d): 1 / 1 = 100.0%"* ]]
}

@test "the instrument's own selftest is green and its background arm has both polarities" {
  run python3 "$INSTRUMENT" --selftest
  [ "$status" -eq 0 ]
  [[ "$output" == *"green"* ]] || false
  # the pristine arm has strictly fewer controls — the fix brought its own
  git -C "$REPO" cat-file -p "$PREFIX_BLOB" > "${BATS_TEST_TMPDIR}/prefix.py"
  run bash -c "python3 '${BATS_TEST_TMPDIR}/prefix.py' --selftest"
  [ "$status" -eq 0 ]
  [[ "$output" == *"7/7"* ]]
}

# ── PART 2: the producer, each case paired with the mutant it guards against ──

mutant() {   # $1 = sed program; echoes the mutant script path
  local prog="$1" dir="${BATS_TEST_TMPDIR}/mut$$_${RANDOM}"
  mkdir -p "$dir"
  # Copied in the SHAPE the subject reads: drain-peer-findings.py resolves its siblings
  # relative to its own __file__ (memory: subject-reads-its-own-path-and-its-own-output).
  cp "$SUT" "${REPO}/scripts/measure-harvest-latency.py" "${REPO}/scripts/measure-closes.py" "$dir/"
  sed -i '' "$prog" "$dir/drain-peer-findings.py"
  printf '%s\n' "$dir/drain-peer-findings.py"
}

@test "the producer's selftest is green" {
  run python3 "$SUT" --selftest
  [ "$status" -eq 0 ]
  [[ "$output" == *"green"* ]]
}

@test "M1 RED-PROOF: harvest evidence may not gate the filing — the mutant that lets it drops a real finding" {
  local mut txt
  txt='row `aaaaaaaaaaaa` proves the converger never ran, so the live layer still remains 27 commits behind its budget'
  # The real rule: EVERY id named must already exist AND the clause must be little more than
  # that list. The mutant relaxes it to ANY id — the lossy form, and the one that skips a real
  # loss whenever the harvest signal is wrong (which is 20% of the time, measured).
  mut="$(mutant 's/    if not all(i in ids for i in found):/    if not any(i in ids for i in found):/; s/return len(residue) <= 60/return True/')"

  run python3 - "$SUT" "$mut" "$txt" <<'PY'
import importlib.util, sys
def load(p):
    s = importlib.util.spec_from_file_location("d"+str(hash(p)), p)
    m = importlib.util.module_from_spec(s); s.loader.exec_module(m); return m
real, mutant, txt = load(sys.argv[1]), load(sys.argv[2]), sys.argv[3]
ids = {"aaaaaaaaaaaa"}
print("real=%s mutant=%s" % (real.already_in_venue(txt, ids), mutant.already_in_venue(txt, ids)))
sys.exit(0 if (real.already_in_venue(txt, ids) is False
               and mutant.already_in_venue(txt, ids) is True) else 1)
PY
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "M1b: a clause naming ONLY ids the ledger already holds is skipped — exact key lookup, not harvest detection" {
  run python3 - "$SUT" <<'PY'
import importlib.util, sys
s = importlib.util.spec_from_file_location("d", sys.argv[1])
m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
ids = {"aaaaaaaaaaaa", "bbbbbbbbbbbb"}
assert m.already_in_venue("`aaaaaaaaaaaa`, `bbbbbbbbbbbb`.", ids) is True
assert m.already_in_venue("`aaaaaaaaaaaa`, `cccccccccccc`.", ids) is False   # one id ABSENT
PY
  [ "$status" -eq 0 ]
}

@test "M2 RED-PROOF: a settled close drains under the mutant with no settled guard, and not under the real script" {
  local mut txt
  txt='Everything of mine is landed; both backlog rows closed and nothing of mine is open, so no loose ends still remain here.'
  # Neutralise only the settled guard, leaving every other rule intact.
  mut="$(mutant 's|_SETTLED\.search(s)|False|g')"

  run python3 - "$SUT" "$mut" "$txt" <<'PY'
import importlib.util, sys
def load(p):
    s = importlib.util.spec_from_file_location("d"+str(hash(p)), p)
    m = importlib.util.module_from_spec(s); s.loader.exec_module(m); return m
real, mutant, txt = load(sys.argv[1]), load(sys.argv[2]), sys.argv[3]
r, mu = real.finding_of(txt), mutant.finding_of(txt)
print("real=%r\nmutant=%r" % (r, mu))
sys.exit(0 if (r == "" and mu != "") else 1)
PY
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "M3 RED-PROOF: a nil follow-on ledger drains under the mutant with no empty-ledger guard" {
  # The ledger must be LONGER than MIN_CLAUSE, or the length check shadows the guard and both
  # arms stay green — which is exactly how this case first failed, and how the guard was found to
  # be dead code anchored at end-of-string.
  local mut txt='Good to close: yes — follow-on: none, everything of mine is landed and content-verified on trunk this turn.'
  mut="$(mutant 's|_NIL_LEAD\.match(cand)|False|')"
  run python3 - "$SUT" "$mut" "$txt" <<'PY'
import importlib.util, sys
def load(p):
    s = importlib.util.spec_from_file_location("d"+str(hash(p)), p)
    m = importlib.util.module_from_spec(s); s.loader.exec_module(m); return m
real, mutant, txt = load(sys.argv[1]), load(sys.argv[2]), sys.argv[3]
r, mu = real.finding_of(txt), mutant.finding_of(txt)
print("real=%r\nmutant=%r" % (r, mu))
sys.exit(0 if (r == "" and mu != "") else 1)
PY
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "a real follow-on ledger IS drained — the guards are not a blanket suppressor" {
  run python3 - "$SUT" <<'INNER'
import importlib.util, sys
s = importlib.util.spec_from_file_location("d", sys.argv[1])
m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
got = m.finding_of("Good to close: yes — follow-on: land the tenant-drift env "
                   "fix, which still remains on its own branch.")
print(repr(got))
sys.exit(0 if "tenant-drift env fix" in got else 1)
INNER
  echo "$output"
  [ "$status" -eq 0 ]
}

# ── PART 2b: the venue. The producer must WRITE THROUGH cc-backlog, never touch the JSONL ──

@test "the drain writes through cc-backlog and never touches the ledger file itself" {
  mk_git_fixture
  local t0; t0="$(python3 -c "import time,datetime;print(datetime.datetime.utcfromtimestamp(time.time()-4*86400).strftime('%Y-%m-%dT%H:%M:%SZ'))")"
  mk_transcript "aaaaaaaa-0000-0000-0000-000000000003" \
    "🔧 Loose ends — \`offbox-core-cure\` still remains unbuilt and is not yet done." \
    "$REPO_FIX" "$t0"
  # Backdate the transcript past the settle window: a warm transcript may still be a live
  # session about to drive its own finding.
  touch -t "$(date -u -v-2d +%Y%m%d%H%M 2>/dev/null || date -u -d '2 days ago' +%Y%m%d%H%M)" \
    "$FAKE/.claude/projects/proj/aaaaaaaa-0000-0000-0000-000000000003.jsonl"

  printf 'PRE-EXISTING\n' > "$LEDGER"
  local stub="${BATS_TEST_TMPDIR}/cc-backlog"
  cat > "$stub" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "${BATS_TEST_TMPDIR}/argv.log"
echo "filed deadbeef0000"
SH
  chmod +x "$stub"

  run env HOME="$FAKE" CC_BACKLOG_FILE="$LEDGER" python3 "$SUT" \
      --days 14 --settle-hours 1 --commit --cc-backlog "$stub"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRAINABLE: 1"* ]] || false
  grep -q -- '--source' "${BATS_TEST_TMPDIR}/argv.log"
  grep -q -- 'peer-drain' "${BATS_TEST_TMPDIR}/argv.log"
  grep -q -- '--falsifier' "${BATS_TEST_TMPDIR}/argv.log"
  # the row is a POINTER: it names the file that holds the whole close
  grep -q 'aaaaaaaa-0000-0000-0000-000000000003.jsonl' "${BATS_TEST_TMPDIR}/argv.log"
  # NO --why-not-now: this is agent work, never an operator ask
  ! grep -q -- '--why-not-now' "${BATS_TEST_TMPDIR}/argv.log" || false
  # and the ledger itself is untouched
  [ "$(cat "$LEDGER")" = "PRE-EXISTING" ]
}

@test "without --commit nothing is written and cc-backlog is never invoked" {
  mk_git_fixture
  local t0; t0="$(python3 -c "import time,datetime;print(datetime.datetime.utcfromtimestamp(time.time()-4*86400).strftime('%Y-%m-%dT%H:%M:%SZ'))")"
  mk_transcript "aaaaaaaa-0000-0000-0000-000000000004" \
    "🔧 Loose ends — \`offbox-core-cure\` still remains unbuilt and is not yet done." \
    "$REPO_FIX" "$t0"
  touch -t "$(date -u -v-2d +%Y%m%d%H%M 2>/dev/null || date -u -d '2 days ago' +%Y%m%d%H%M)" \
    "$FAKE/.claude/projects/proj/aaaaaaaa-0000-0000-0000-000000000004.jsonl"
  local stub="${BATS_TEST_TMPDIR}/cc-backlog"
  printf '#!/usr/bin/env bash\ntouch "${BATS_TEST_TMPDIR}/INVOKED"\n' > "$stub"; chmod +x "$stub"

  run env HOME="$FAKE" CC_BACKLOG_FILE="$LEDGER" python3 "$SUT" \
      --days 14 --settle-hours 1 --cc-backlog "$stub"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY RUN"* ]] || false
  [ ! -e "${BATS_TEST_TMPDIR}/INVOKED" ]
}

@test "a still-warm transcript is not drained — a live session may yet drive its own finding" {
  mk_git_fixture
  local t0; t0="$(python3 -c "import time,datetime;print(datetime.datetime.utcfromtimestamp(time.time()-4*86400).strftime('%Y-%m-%dT%H:%M:%SZ'))")"
  mk_transcript "aaaaaaaa-0000-0000-0000-000000000005" \
    "🔧 Loose ends — \`offbox-core-cure\` still remains unbuilt and is not yet done." \
    "$REPO_FIX" "$t0"
  # left at mtime=now, i.e. warm
  run env HOME="$FAKE" CC_BACKLOG_FILE="$LEDGER" python3 "$SUT" --days 14 --settle-hours 6
  [ "$status" -eq 0 ]
  echo "$output"
  [[ "$output" == *"DRAINABLE: 0"* ]] || false
  [[ "$output" == *"skipped 1 still warm"* ]]
}

@test "the mid-turn-death population is reachable, and OFF by default" {
  mk_git_fixture
  # a transcript with assistant text but NO turn-final close: a tool_use block means the turn
  # never ended, which is exactly the 302/820 shape.
  python3 - "$FAKE/.claude/projects/proj/aaaaaaaa-0000-0000-0000-000000000006.jsonl" "$REPO_FIX" <<'PY'
import json, sys
path, cwd = sys.argv[1], sys.argv[2]
recs = [
  {"type": "user", "cwd": cwd, "timestamp": "2026-09-05T00:00:00Z",
   "message": {"role": "user", "content": "go"}},
  {"type": "assistant", "cwd": cwd, "timestamp": "2026-09-05T00:00:01Z",
   "message": {"id": "m1", "role": "assistant", "content": [
     {"type": "text", "text": "🔧 the offbox-core-cure rebuild still remains unfinished here."},
     {"type": "tool_use", "id": "t1", "name": "Bash", "input": {}}]}},
]
open(path, "w").write("\n".join(json.dumps(r) for r in recs) + "\n")
PY
  touch -t "$(date -u -v-2d +%Y%m%d%H%M 2>/dev/null || date -u -d '2 days ago' +%Y%m%d%H%M)" \
    "$FAKE/.claude/projects/proj/aaaaaaaa-0000-0000-0000-000000000006.jsonl"

  run env HOME="$FAKE" CC_BACKLOG_FILE="$LEDGER" python3 "$SUT" --days 14 --settle-hours 1
  [ "$status" -eq 0 ]
  echo "DEFAULT: $output"
  [[ "$output" == *"skipped 1 with no turn-final close"* ]] || false
  [[ "$output" == *"DRAINABLE: 0"* ]] || false

  run env HOME="$FAKE" CC_BACKLOG_FILE="$LEDGER" python3 "$SUT" \
      --days 14 --settle-hours 1 --include-no-close
  [ "$status" -eq 0 ]
  echo "OPTED IN: $output"
  [[ "$output" == *"DRAINABLE: 1"* ]] || false
  [[ "$output" == *"1 from a mid-turn death"* ]]
}
