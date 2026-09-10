#!/usr/bin/env bats
# peer-owned.sh — LIVE-PEER-OWNED attribution for the 📦 term of completion-assert.sh.
#
# The subject answers "are this tree's unlanded commits owned by a DIFFERENT, still-LIVE session?".
# Reproduces the measured 2026-08-03 conviction (a read-only session blocked 3/3 for a live peer's
# 7h/10h-old commits) and — more importantly — pins the CONTROLS, because every one of them is a
# way this could silently become a blanket exoneration:
#   · the peer is DEAD  ⇒ the /handoff + --recycle successor shape, which MUST still be convicted;
#   · this session WROTE a path in the unlanded diff;
#   · this session RAN `git commit`, the residue the transcript's file-edit records cannot see;
#   · the peer started AFTER the commit, so it cannot have made it;
#   · the peer is in another repo, or is this session itself;
#   · nothing readable at all ⇒ cannot-tell, never an exoneration.
# The fix is fail-GREEN by construction (it withholds a block), so the controls carry the weight.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/hooks/lib/peer-owned.sh"
  # $HOME FIRST, and it is not ceremony here: the subject's registry path DEFAULTS to
  # $HOME/.claude/cc-registry, and both lib path-fallback chains end under $HOME. Unfixtured, a
  # missing CC_REGISTRY_DIR would silently read the operator's live fleet.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export SESSION_WRITES_LIB="$REPO/hooks/lib/session-writes.sh"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"
  mkdir -p "$CC_REGISTRY_DIR"
  NOW="$(date +%s)"
  T_COMMIT=$(( NOW - 36000 ))     # the unlanded commit — 10h ago, as in the incident
  T_PEER=$(( NOW - 61200 ))       # the peer — 17h ago, so it was running when the commit was made
  T_LATEPEER=$(( NOW - 3600 ))    # a peer that started AFTER the commit
  T_OLDSESS=$(( NOW - 86400 ))    # this session predates the commits ⇒ forces the (1b) proof
  T_NEWSESS=$(( NOW - 7200 ))     # this session postdates them ⇒ (1a) proves non-authorship alone
}

teardown() {
  [ -f "$BATS_TEST_TMPDIR/pids" ] || return 0
  local p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    kill "$p" 2>/dev/null || true
    wait "$p" 2>/dev/null || true
  done < "$BATS_TEST_TMPDIR/pids"
}

# A LIVE pid. `sleep` is enough: the subject's liveness oracle is `kill -0`, deliberately the same
# one bin/cc-sessions calls authoritative, so the fixture does not have to impersonate a session.
#
# `>/dev/null 2>&1` ON THE BACKGROUND JOB IS LOAD-BEARING. These helpers are called inside `$( )`,
# and a command substitution does not return when its child exits — it returns when the last writer
# to the captured pipe closes it. A backgrounded `sleep 300` inherits that pipe, so without the
# redirect the substitution blocks for the full 300s and the suite hangs with no output at all
# (measured: the first run of this file was killed at 120s having printed nothing).
_po_live_pid() {
  sleep 300 >/dev/null 2>&1 &
  local p=$!
  printf '%s\n' "$p" >> "$BATS_TEST_TMPDIR/pids"
  printf '%s' "$p"
}

# A pid that is definitely gone AND REAPED. The reap is load-bearing, not tidiness: an unreaped
# zombie still answers `kill -0` with rc 0, so killing without waiting would fixture a "dead" peer
# that the subject correctly reads as alive (MEMORY.md kill-on-reaped-child-fails-fast-path-hides-it).
_po_dead_pid() {
  sleep 300 >/dev/null 2>&1 &
  local p=$!
  kill "$p" 2>/dev/null || true
  wait "$p" 2>/dev/null || true
  printf '%s' "$p"
}

_po_reg() { # <paneUUID> <pid> <startedAt_epoch> <cwd> <session_id>
  jq -nc --arg u "$1" --arg n "claude-peer-$1" --arg c "$4" --arg s "$5" \
         --argjson p "$2" --argjson t "$(( $3 * 1000 ))" \
    '{paneUUID:$u,name:$n,cwd:$c,account:"a",pid:$p,startedAt:$t,session_id:$s}' \
    > "$CC_REGISTRY_DIR/$1.json"
}

# A repo with origin/main plus ONE unlanded commit, made at a controlled committer date.
_po_repo() { # <tag> <commit_epoch> <path-in-repo>
  local o="$BATS_TEST_TMPDIR/o-$1.git" w="$BATS_TEST_TMPDIR/w-$1"
  git init -q --bare "$o"; git clone -q "$o" "$w" 2>/dev/null
  ( cd "$w" || exit 1
    git config user.email t@e.com; git config user.name t; git checkout -q -b main
    echo base > base.txt; git add -A; git commit -q -m base; git push -q -u origin main
    mkdir -p "$(dirname "$3")" 2>/dev/null || true
    echo x > "$3"; git add -A
    GIT_COMMITTER_DATE="@$2 +0000" GIT_AUTHOR_DATE="@$2 +0000" git commit -q -m "peer work"
  ) >/dev/null 2>&1
  printf '%s' "$w"
}

# A transcript whose FIRST record carries <ts>, then zero or more `--write <path>` / `--bash <cmd>`
# tool_use records, then a done-assertion.
_po_tx() { # <out> <first_ts_epoch> [--write P | --bash CMD]...
  local out="$1"; shift
  python3 - "$out" "$@" <<'PY'
import json, sys, time
out, ts, args = sys.argv[1], int(sys.argv[2]), sys.argv[3:]
iso = time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(ts)) + ".000Z"
rows = [{"type": "user", "timestamp": iso, "message": {"content": "go"}}]
for kind, val in zip(args[0::2], args[1::2]):
    tool = {"--write": ("Edit", "file_path"), "--bash": ("Bash", "command")}[kind]
    rows.append({"type": "assistant", "timestamp": iso, "message": {"content": [
        {"type": "tool_use", "name": tool[0], "input": {tool[1]: val}}]}})
rows.append({"type": "assistant", "timestamp": iso, "message": {"content": [
    {"type": "text", "text": "✅ Complete — all done."}]}})
open(out, "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
PY
  printf '%s' "$out"
}

po() { # <repo> <session_id> <transcript>
  run bash -c ". '$LIB'; peer_owned_unlanded '$1' origin/main '$2' '$3'"
}

# ── THE MEASURED INCIDENT ────────────────────────────────────────────────────────────────────────
# Session claude-infrastructure-323: read-only research turn, clean tree, ZERO files written, in the
# shared checkout, over two commits made by claude-infrastructure-234 while it was still running.
# The session is OLDER than the commits here, so (1a) cannot help and the verdict rests entirely on
# (1b) — provably wrote nothing and ran no commit-producing command — which is the incident's shape.
@test "the incident: a write-free session over a LIVE peer's older commits ⇒ live-peer-owned" {
  local w; w="$(_po_repo inc "$T_COMMIT" config/kitty.conf)"
  _po_reg 234 "$(_po_live_pid)" "$T_PEER" "$w" peer-234
  po "$w" mine-323 "$(_po_tx "$BATS_TEST_TMPDIR/inc.jsonl" "$T_OLDSESS")"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'claude-peer-234#'
}

# ── THE CONTROL THAT MATTERS MOST ────────────────────────────────────────────────────────────────
# A /handoff or `handoff-fire.sh --recycle` successor inherits its predecessor's unlanded commits
# and its whole job is to land them. It did not author them either, so exonerating on non-authorship
# alone would retire the 📦 rung for exactly the case it exists for. The ONLY thing separating that
# session from the incident's is whether the other party is still running.
@test "CONTROL: the same commits with the peer DEAD ⇒ NOT peer-owned (a successor must still land)" {
  local w; w="$(_po_repo dead "$T_COMMIT" config/kitty.conf)"
  _po_reg 234 "$(_po_dead_pid)" "$T_PEER" "$w" peer-234
  po "$w" mine-323 "$(_po_tx "$BATS_TEST_TMPDIR/dead.jsonl" "$T_OLDSESS")"
  [ "$status" -eq 1 ]
}

@test "CONTROL: this session WROTE a path in the unlanded diff ⇒ NOT peer-owned" {
  local w; w="$(_po_repo mine "$T_COMMIT" config/kitty.conf)"
  _po_reg 234 "$(_po_live_pid)" "$T_PEER" "$w" peer-234
  po "$w" mine-323 "$(_po_tx "$BATS_TEST_TMPDIR/mine.jsonl" "$T_OLDSESS" --write "$w/config/kitty.conf")"
  [ "$status" -eq 1 ]
}

# The residue session-writes.sh names by name: a file written only through Bash is invisible to the
# file-edit records. For COMMIT authorship that residue is closable, and this is the proof.
@test "CONTROL: a write-free session that RAN git commit ⇒ NOT peer-owned" {
  local w; w="$(_po_repo bash "$T_COMMIT" config/kitty.conf)"
  _po_reg 234 "$(_po_live_pid)" "$T_PEER" "$w" peer-234
  po "$w" mine-323 "$(_po_tx "$BATS_TEST_TMPDIR/bash.jsonl" "$T_OLDSESS" --bash 'git commit -q -m "work"')"
  [ "$status" -eq 1 ]
}

# …and the pairing control for the same scan, or it would just be an over-broad ban on the word.
# `[^;&|]` bounds the match to ONE command in a chain, so the second stage of a pipeline is not
# read as the first one's verb — a read-only session greping its own log is the incident's session.
@test "a piped 'git log | grep commit' is not a commit — the pipe bounds the scan" {
  local w; w="$(_po_repo pipe "$T_COMMIT" config/kitty.conf)"
  _po_reg 234 "$(_po_live_pid)" "$T_PEER" "$w" peer-234
  po "$w" mine-323 "$(_po_tx "$BATS_TEST_TMPDIR/pipe.jsonl" "$T_OLDSESS" --bash 'git log --oneline | grep commit')"
  [ "$status" -eq 0 ]
}

# ── (1a), the other disjunct: an ordering fact no tool residue can defeat ────────────────────────
# Here the session is NEWER than the commits, so it could not have made them however it wrote files
# — and it did write one. This is the branch that survives an unreadable transcript, where (1b)
# cannot answer at all.
@test "(1a): every unlanded commit predates this session ⇒ peer-owned even though it wrote files" {
  local w; w="$(_po_repo pre "$T_COMMIT" config/kitty.conf)"
  _po_reg 234 "$(_po_live_pid)" "$T_PEER" "$w" peer-234
  po "$w" mine-323 "$(_po_tx "$BATS_TEST_TMPDIR/pre.jsonl" "$T_NEWSESS" --write "$w/notes.md")"
  [ "$status" -eq 0 ]
}

@test "CONTROL: a peer that started AFTER the oldest unlanded commit cannot own it" {
  local w; w="$(_po_repo late "$T_COMMIT" config/kitty.conf)"
  _po_reg 234 "$(_po_live_pid)" "$T_LATEPEER" "$w" peer-234
  po "$w" mine-323 "$(_po_tx "$BATS_TEST_TMPDIR/late.jsonl" "$T_OLDSESS")"
  [ "$status" -eq 1 ]
}

# A worktree has its own toplevel, so a peer working in one is NOT a peer in this tree — which is
# what keeps this scoped to the shared-checkout case it was built for.
@test "CONTROL: a live peer whose cwd is a DIFFERENT repo does not own these commits" {
  local w o; w="$(_po_repo other "$T_COMMIT" config/kitty.conf)"; o="$BATS_TEST_TMPDIR/elsewhere"
  mkdir -p "$o"
  _po_reg 234 "$(_po_live_pid)" "$T_PEER" "$o" peer-234
  po "$w" mine-323 "$(_po_tx "$BATS_TEST_TMPDIR/other.jsonl" "$T_OLDSESS")"
  [ "$status" -eq 1 ]
}

@test "CONTROL: the only live row is THIS session — a session cannot be its own peer" {
  local w; w="$(_po_repo self "$T_COMMIT" config/kitty.conf)"
  _po_reg 323 "$(_po_live_pid)" "$T_PEER" "$w" mine-323
  po "$w" mine-323 "$(_po_tx "$BATS_TEST_TMPDIR/self.jsonl" "$T_OLDSESS")"
  [ "$status" -eq 1 ]
}

@test "no registry at all ⇒ cannot-tell (rc 2), never an exoneration" {
  local w; w="$(_po_repo noreg "$T_COMMIT" config/kitty.conf)"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/absent"
  po "$w" mine-323 "$(_po_tx "$BATS_TEST_TMPDIR/noreg.jsonl" "$T_OLDSESS")"
  [ "$status" -eq 2 ]
}

# Nothing ahead of trunk ⇒ there is no commit to attribute, so this oracle has no verdict to give.
# UNLANDED can still be 1 in that state (wrap-ledger's cherry/content check), and answering "owned"
# over an empty set would exonerate content-stranded work the ledger caught by other means.
@test "no commits ahead of trunk ⇒ cannot-tell, not an exoneration" {
  local o="$BATS_TEST_TMPDIR/o-empty.git" w="$BATS_TEST_TMPDIR/w-empty"
  git init -q --bare "$o"; git clone -q "$o" "$w" 2>/dev/null
  ( cd "$w" || exit 1; git config user.email t@e.com; git config user.name t
    git checkout -q -b main; echo base > base.txt; git add -A; git commit -q -m base
    git push -q -u origin main ) >/dev/null 2>&1
  _po_reg 234 "$(_po_live_pid)" "$T_PEER" "$w" peer-234
  po "$w" mine-323 "$(_po_tx "$BATS_TEST_TMPDIR/empty.jsonl" "$T_OLDSESS")"
  [ "$status" -eq 2 ]
}

# ── dirt_predates_session — the 🔧 term's ordering proof (2026-08-11) ─────────────────────────────
# Reproduces the measured conviction of a write-free session over a sibling's dirty tree (backlog
# ce91e9583df1, cause-isolated in 9be5e66e1c34) and pins the controls that keep it from becoming a
# blanket exoneration. As with the peer term above, the fix is fail-GREEN by construction — it
# withholds a block — so the REFUTING cases carry the weight, not the positive one.

# A landed, clean repo. The tests dirty it themselves so each owns the mtimes it asserts on.
# The identity is passed transiently (`-c`) rather than written with `git config`: these fixtures
# are throwaway clones, and the repo-wide ban on untargeted identity writes exists because this
# checkout's ~100 linked worktrees share one .git/config.
_po_clean_repo() { # <tag> → echoes the worktree
  local o="$BATS_TEST_TMPDIR/o-$1.git" w="$BATS_TEST_TMPDIR/w-$1"
  git init -q --bare "$o"; git clone -q "$o" "$w" 2>/dev/null
  git -C "$w" checkout -q -b main
  # TWO tracked files, because the deletion control below needs a deleted path AND a surviving
  # old one in the same status stream — with only base.txt, deleting it empties the population and
  # the test would pass through the `n == 0` branch instead of the branch it names (measured: that
  # exact fixture let the "deletion treated as old" mutant survive the screen).
  echo base > "$w/base.txt"; echo second > "$w/second.txt"; git -C "$w" add -A
  git -C "$w" -c user.email=t@e.com -c user.name=t commit -q -m base >/dev/null 2>&1
  git -C "$w" push -q -u origin main >/dev/null 2>&1
  printf '%s' "$w"
}

# `touch -t` takes a wall-clock stamp, not an epoch — `touch -d @epoch` is GNU-only. BSD `date -r`
# first (this fleet is macOS), GNU `date -d @…` second.
_po_touch_at() { # <epoch> <file>
  local s; s="$(date -r "$1" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$1" +%Y%m%d%H%M.%S 2>/dev/null)"
  [ -n "$s" ] || return 1
  touch -t "$s" "$2"
}

dps() { # <repo> <session_id> <transcript>
  run bash -c ". '$LIB'; dirt_predates_session '$1' '$2' '$3'"
}

# THE MEASURED CASE: session 44dc8891 wrote nothing; the 4 dirty files were a sibling's, already on
# disk when it started. The ordering fact settles it without any liveness question.
@test "the incident: every dirty path predates this session's start ⇒ exonerated" {
  local w; w="$(_po_clean_repo dps1)"
  echo sibling >> "$w/base.txt"
  _po_touch_at "$(( T_NEWSESS - 3600 ))" "$w/base.txt"
  dps "$w" mine-1 "$(_po_tx "$BATS_TEST_TMPDIR/dps1.jsonl" "$T_NEWSESS")"
  [ "$status" -eq 0 ]
  [[ "$output" == paths=1,* ]]
}

# THE CONTROL THAT MATTERS MOST — dirt made after this session started is exactly the case the
# guard exists for, and the Bash residue (`sed -i`, a heredoc) lands here with no tool_use record.
@test "CONTROL: dirt stamped AFTER the session started ⇒ refuted, the guard still convicts" {
  local w; w="$(_po_clean_repo dps2)"
  echo mine >> "$w/base.txt"
  _po_touch_at "$(( T_NEWSESS + 60 ))" "$w/base.txt"
  dps "$w" mine-2 "$(_po_tx "$BATS_TEST_TMPDIR/dps2.jsonl" "$T_NEWSESS")"
  [ "$status" -eq 1 ]
}

# ONE new path among old ones must convict the whole tree: the ledger's DIRTY term is binary, so a
# per-path exoneration that ignored the newest file would clear a real loose end.
@test "CONTROL: one new path among several old ones ⇒ refuted" {
  local w; w="$(_po_clean_repo dps3)"
  echo a >> "$w/base.txt"; echo b > "$w/old-untracked.txt"; echo c > "$w/new-untracked.txt"
  _po_touch_at "$(( T_NEWSESS - 3600 ))" "$w/base.txt"
  _po_touch_at "$(( T_NEWSESS - 3600 ))" "$w/old-untracked.txt"
  _po_touch_at "$(( T_NEWSESS + 60 ))"   "$w/new-untracked.txt"
  dps "$w" mine-3 "$(_po_tx "$BATS_TEST_TMPDIR/dps3.jsonl" "$T_NEWSESS")"
  [ "$status" -eq 1 ]
}

# Same-second equality is REFUTED, not exonerated: mtime granularity is one second, so `==` cannot
# tell "written just before the session" from "written by it".
@test "CONTROL: an mtime EQUAL to the session start is refuted, not exonerated" {
  local w; w="$(_po_clean_repo dps4)"
  echo x >> "$w/base.txt"
  _po_touch_at "$T_NEWSESS" "$w/base.txt"
  dps "$w" mine-4 "$(_po_tx "$BATS_TEST_TMPDIR/dps4.jsonl" "$T_NEWSESS")"
  [ "$status" -eq 1 ]
}

# -uall: git's DEFAULT untracked mode collapses a wholly untracked directory to one record (`?? d/`),
# whose mtime is the DIRECTORY's. A new file in a new directory would then be judged on the dir and
# could read as old — the fail-GREEN trap session_dirty_mine documents, arriving here by a new route.
@test "CONTROL: a NEW file inside a NEW untracked directory is seen and refutes" {
  local w; w="$(_po_clean_repo dps5)"
  mkdir -p "$w/fresh"; echo n > "$w/fresh/mine.ts"
  _po_touch_at "$(( T_NEWSESS + 60 ))" "$w/fresh/mine.ts"
  _po_touch_at "$(( T_NEWSESS - 3600 ))" "$w/fresh"
  dps "$w" mine-5 "$(_po_tx "$BATS_TEST_TMPDIR/dps5.jsonl" "$T_NEWSESS")"
  [ "$status" -eq 1 ]
}

# A DELETION has no mtime. Treating an absent file as ancient is how this would exonerate a session
# that had just `rm`'d something, so it is cannot-tell.
# THE OLD FILE BESIDE IT IS THE WHOLE POINT of the fixture. With the deletion alone the population
# is empty and rc 2 arrives from the `n == 0` branch, so the test passes whether or not the deletion
# is handled — vacuously. With a surviving old path, skipping the deletion instead of abstaining
# yields rc 0 (exonerate), which is the failure this control is named for.
@test "CONTROL: a deleted tracked file ⇒ cannot-tell, never 'old'" {
  local w; w="$(_po_clean_repo dps6)"
  rm -f "$w/base.txt"
  echo old >> "$w/second.txt"
  _po_touch_at "$(( T_NEWSESS - 3600 ))" "$w/second.txt"
  dps "$w" mine-6 "$(_po_tx "$BATS_TEST_TMPDIR/dps6.jsonl" "$T_NEWSESS")"
  [ "$status" -eq 2 ]
}

# An empty population cannot produce a verdict — returning 0 over no dirty paths would manufacture
# an exoneration (MEMORY.md cap-whose-population-is-empty).
@test "CONTROL: a CLEAN tree ⇒ cannot-tell, not an exoneration" {
  local w; w="$(_po_clean_repo dps7)"
  dps "$w" mine-7 "$(_po_tx "$BATS_TEST_TMPDIR/dps7.jsonl" "$T_NEWSESS")"
  [ "$status" -eq 2 ]
}

# Ignorance never exonerates: with no timestamp in the transcript and no registry row, the session
# start is unresolvable and the term must abstain rather than guess.
@test "CONTROL: unresolvable session start ⇒ cannot-tell" {
  local w; w="$(_po_clean_repo dps8)"
  echo sibling >> "$w/base.txt"
  _po_touch_at "$(( T_NEWSESS - 3600 ))" "$w/base.txt"
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"done"}]}}' \
    > "$BATS_TEST_TMPDIR/dps8.jsonl"
  dps "$w" mine-8 "$BATS_TEST_TMPDIR/dps8.jsonl"
  [ "$status" -eq 2 ]
}

# ── dirt_outside_session_execution — the residue the ordering proof named (2026-08-12) ───────────
# The subject answers "was every dirty path stamped while this session was demonstrably executing
# NOTHING?".  It exists because ordering only ever covers dirt OLDER than the session, and the
# measured ORIGIN conviction (claude-infrastructure-387, backlog 76e444a40188) was the other shape:
# a live sibling's work made 38 minutes INTO a zero-write read-only run.
#
# REPLAYED AGAINST THE REAL ARTEFACT before these fixtures were written — session 387's own
# transcript, truncated to its state at the third Stop block: dirt stamped 23:10:00Z (a gap) ⇒ rc 0,
# the same transcript with dirt stamped 23:17:12Z (inside a real 3-second window) ⇒ rc 1.
# Every control below is a way this could become a blanket exoneration, which is the only direction
# that matters: like its siblings the fix is fail-GREEN — it withholds a block.

# A transcript with a controlled first/last record and EXPLICIT Bash execution windows.
#   --win A B   a Bash tool_use at A paired with its tool_result at B
#   --open A    a Bash tool_use at A with NO tool_result (interrupt/kill ⇒ an open window)
#   --bg A B    a --win whose input carries run_in_background: true
#   --write P   a file-edit tool_use, i.e. the session is no longer write-free (NO id ⇒ unpaired)
#   --edit P A B / --tool NAME A B / --sub A B / --subedit P A B   see the python below
_po_tx_exec() { # <out> <first_ts> <last_ts> [--win A B | --open A | --bg A B | --write P]...
  local out="$1"; shift
  python3 - "$out" "$@" <<'PY'
import json, sys, time
out, first, last, args = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4:]
def iso(t): return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(int(t))) + ".000Z"
def rec(ts, content): return {"type": "assistant", "timestamp": iso(ts),
                              "message": {"content": [content]}}
rows = [{"type": "user", "timestamp": iso(first), "message": {"content": "go"}}]
sub = []          # records of ONE subagent, written to <out-sans-.jsonl>/subagents/agent-a1.jsonl
i = n = 0
def pair(dst, name, inp, a, b):
    global n
    n += 1
    tid = "t%d" % n
    r = rec(a, {"type": "tool_use", "id": tid, "name": name, "input": inp})
    if dst is sub: r["isSidechain"] = True
    dst.append(r)
    if b is not None:
        u = {"type": "user", "timestamp": iso(b), "message": {"content": [
             {"type": "tool_result", "tool_use_id": tid, "content": "ok"}]}}
        if dst is sub: u["isSidechain"] = True
        dst.append(u)
while i < len(args):
    kind = args[i]
    if kind == "--write":
        rows.append(rec(first, {"type": "tool_use", "name": "Edit",
                                "input": {"file_path": args[i + 1]}}))
        i += 2
        continue
    # --edit P A B     a real, id-paired Edit of P (the --write above has no id ⇒ an OPEN window)
    # --tool NAME A B  a paired window of any other tool
    # --sub A B        a Bash window inside the SUBAGENT file
    # --subedit P A B  an Edit of P inside the SUBAGENT file
    if kind == "--edit":
        pair(rows, "Edit", {"file_path": args[i + 1]}, args[i + 2], args[i + 3]); i += 4; continue
    if kind == "--tool":
        inp = {"run_in_background": True} if args[i + 1] == "Agent-bg" else {}
        name = "Agent" if args[i + 1] == "Agent-bg" else args[i + 1]
        pair(rows, name, inp, args[i + 2], args[i + 3]); i += 4; continue
    if kind == "--sub":
        pair(sub, "Bash", {"command": "sed -i s/a/b/ f"}, args[i + 1], args[i + 2]); i += 3; continue
    if kind == "--subedit":
        pair(sub, "Edit", {"file_path": args[i + 1]}, args[i + 2], args[i + 3]); i += 4; continue
    bg = (kind == "--bg")
    inp = {"command": "git status"}
    if bg:
        inp["run_in_background"] = True
    if kind == "--open":
        pair(rows, "Bash", inp, args[i + 1], None); i += 2; continue
    pair(rows, "Bash", inp, args[i + 1], args[i + 2])
    i += 3
rows.append(rec(last, {"type": "text", "text": "✅ Complete — all done."}))
open(out, "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
if sub:
    import os
    d = out[:-len(".jsonl")] + "/subagents"
    os.makedirs(d, exist_ok=True)
    open(d + "/agent-a1.jsonl", "w").write("\n".join(json.dumps(r) for r in sub) + "\n")
PY
  printf '%s' "$out"
}

dox() { # <repo> <transcript>
  run bash -c ". '$LIB'; dirt_outside_session_execution '$1' '$2'"
}

# THE MEASURED CASE: a read-only ORIGIN session, no file-edit record anywhere, and a sibling's dirt
# stamped in a gap between two of its commands. Ordering cannot help — the dirt is NEWER than the
# session — so this is the only term that can reach it.
@test "the residue case: dirt stamped between this session's commands ⇒ exonerated" {
  local w tr; w="$(_po_clean_repo dox1)"
  echo sibling >> "$w/base.txt"
  _po_touch_at "$(( NOW - 1800 ))" "$w/base.txt"
  tr="$(_po_tx_exec "$BATS_TEST_TMPDIR/dox1.jsonl" "$(( NOW - 3600 ))" "$(( NOW - 10 ))" \
        --win "$(( NOW - 2400 ))" "$(( NOW - 2395 ))" --win "$(( NOW - 600 ))" "$(( NOW - 595 ))")"
  dox "$w" "$tr"
  [ "$status" -eq 0 ]
  [[ "$output" == paths=1,windows=2,* ]]
}

# THE CONTROL THE TERM LIVES OR DIES BY — clause (3). This is where a Bash `sed -i` lands: it leaves
# no tool_use record of the WRITE, but it cannot run outside its own command's window, so the mtime
# falls inside one and the guard must still convict.
@test "CONTROL: dirt stamped INSIDE an execution window ⇒ refuted, the guard still convicts" {
  local w tr; w="$(_po_clean_repo dox2)"
  echo mine >> "$w/base.txt"
  _po_touch_at "$(( NOW - 2398 ))" "$w/base.txt"
  tr="$(_po_tx_exec "$BATS_TEST_TMPDIR/dox2.jsonl" "$(( NOW - 3600 ))" "$(( NOW - 10 ))" \
        --win "$(( NOW - 2400 ))" "$(( NOW - 2395 ))")"
  dox "$w" "$tr"
  [ "$status" -eq 1 ]
}

# A tool_use with no tool_result (interrupt, kill, a session that died mid-command) is an OPEN
# window running to +∞, never a skipped one — the miss direction of a skip is exoneration.
@test "CONTROL: a Bash call with NO tool_result is an open window ⇒ refuted" {
  local w tr; w="$(_po_clean_repo dox3)"
  echo mine >> "$w/base.txt"
  _po_touch_at "$(( NOW - 600 ))" "$w/base.txt"
  tr="$(_po_tx_exec "$BATS_TEST_TMPDIR/dox3.jsonl" "$(( NOW - 3600 ))" "$(( NOW - 10 ))" \
        --open "$(( NOW - 1200 ))")"
  dox "$w" "$tr"
  [ "$status" -eq 1 ]
}

# Clause (2), upper bound: a transcript is evidence only about the interval it spans. Dirt stamped
# after its last record postdates every window it can enumerate ⇒ cannot-tell, never "a gap".
@test "CONTROL: dirt stamped AFTER the last record ⇒ cannot-tell" {
  local w tr; w="$(_po_clean_repo dox4)"
  echo x >> "$w/base.txt"
  _po_touch_at "$(( NOW - 5 ))" "$w/base.txt"
  tr="$(_po_tx_exec "$BATS_TEST_TMPDIR/dox4.jsonl" "$(( NOW - 3600 ))" "$(( NOW - 600 ))" \
        --win "$(( NOW - 2400 ))" "$(( NOW - 2395 ))")"
  dox "$w" "$tr"
  [ "$status" -eq 2 ]
}

# Clause (2), lower bound — and this is the /compact case, not a corner: a compaction truncates the
# early records, so the region before the first one is one this file can say NOTHING about. (Dirt
# there is dirt_predates_session's question, and it answers rc 0 on exactly this shape.)
@test "CONTROL: dirt stamped BEFORE the first record ⇒ cannot-tell" {
  local w tr; w="$(_po_clean_repo dox5)"
  echo x >> "$w/base.txt"
  _po_touch_at "$(( NOW - 7200 ))" "$w/base.txt"
  tr="$(_po_tx_exec "$BATS_TEST_TMPDIR/dox5.jsonl" "$(( NOW - 3600 ))" "$(( NOW - 10 ))" \
        --win "$(( NOW - 2400 ))" "$(( NOW - 2395 ))")"
  dox "$w" "$tr"
  [ "$status" -eq 2 ]
}

# Clause (1). A session that wrote ANYTHING has an intersection for session_dirty_mine to compute,
# and this term must never pre-empt it — the written path is deliberately not the dirty one, so only
# the clause can keep this from exonerating.
@test "CONTROL: a session with any file-edit record ⇒ cannot-tell, never this term's business" {
  local w tr; w="$(_po_clean_repo dox6)"
  echo x >> "$w/base.txt"
  _po_touch_at "$(( NOW - 1800 ))" "$w/base.txt"
  tr="$(_po_tx_exec "$BATS_TEST_TMPDIR/dox6.jsonl" "$(( NOW - 3600 ))" "$(( NOW - 10 ))" \
        --win "$(( NOW - 2400 ))" "$(( NOW - 2395 ))" --write /tmp/elsewhere.txt)"
  dox "$w" "$tr"
  [ "$status" -eq 2 ]
}

# Clause (4). A detached command outlives its window, so the whole time argument stops holding —
# ONE such record anywhere in the transcript is enough to abstain for the entire session.
@test "CONTROL: a backgrounded Bash call anywhere ⇒ cannot-tell for the whole session" {
  local w tr; w="$(_po_clean_repo dox7)"
  echo x >> "$w/base.txt"
  _po_touch_at "$(( NOW - 1800 ))" "$w/base.txt"
  tr="$(_po_tx_exec "$BATS_TEST_TMPDIR/dox7.jsonl" "$(( NOW - 3600 ))" "$(( NOW - 10 ))" \
        --bg "$(( NOW - 2400 ))" "$(( NOW - 2395 ))")"
  dox "$w" "$tr"
  [ "$status" -eq 2 ]
}

# The DIRTY term is binary, so one reachable path must convict the whole tree — a per-path
# exoneration that ignored it would clear a real loose end.
@test "CONTROL: one path inside a window among several outside ⇒ refuted" {
  local w tr; w="$(_po_clean_repo dox8)"
  echo a >> "$w/base.txt"; echo b > "$w/gap.txt"; echo c > "$w/inside.txt"
  _po_touch_at "$(( NOW - 1800 ))" "$w/base.txt"
  _po_touch_at "$(( NOW - 1700 ))" "$w/gap.txt"
  _po_touch_at "$(( NOW - 2398 ))" "$w/inside.txt"
  tr="$(_po_tx_exec "$BATS_TEST_TMPDIR/dox8.jsonl" "$(( NOW - 3600 ))" "$(( NOW - 10 ))" \
        --win "$(( NOW - 2400 ))" "$(( NOW - 2395 ))")"
  dox "$w" "$tr"
  [ "$status" -eq 1 ]
}

# A deletion has no mtime. THE OLD FILE BESIDE IT IS THE POINT of the fixture, exactly as in the
# ordering term's twin: with the deletion alone the population is empty and rc 2 arrives from the
# `n == 0` branch, so the test would pass whether or not the deletion is handled.
@test "CONTROL: a deleted tracked file ⇒ cannot-tell, never a gap" {
  local w tr; w="$(_po_clean_repo dox9)"
  rm -f "$w/base.txt"
  echo x >> "$w/second.txt"
  _po_touch_at "$(( NOW - 1800 ))" "$w/second.txt"
  tr="$(_po_tx_exec "$BATS_TEST_TMPDIR/dox9.jsonl" "$(( NOW - 3600 ))" "$(( NOW - 10 ))" \
        --win "$(( NOW - 2400 ))" "$(( NOW - 2395 ))")"
  dox "$w" "$tr"
  [ "$status" -eq 2 ]
}

# An empty population manufactures an exoneration out of nothing (MEMORY.md
# cap-whose-population-is-empty).
@test "CONTROL: a CLEAN tree ⇒ cannot-tell, not an exoneration (execution term)" {
  local w tr; w="$(_po_clean_repo dox10)"
  tr="$(_po_tx_exec "$BATS_TEST_TMPDIR/dox10.jsonl" "$(( NOW - 3600 ))" "$(( NOW - 10 ))" \
        --win "$(( NOW - 2400 ))" "$(( NOW - 2395 ))")"
  dox "$w" "$tr"
  [ "$status" -eq 2 ]
}

# THE 9 FIXTURES STAY STRICT, by the same mechanism the ordering term relies on: a transcript with
# no `.timestamp` anywhere brackets nothing, so clause (2) can never be satisfied.
@test "CONTROL: a transcript with NO timestamps ⇒ cannot-tell" {
  local w; w="$(_po_clean_repo dox11)"
  echo x >> "$w/base.txt"
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"done"}]}}' \
    > "$BATS_TEST_TMPDIR/dox11.jsonl"
  dox "$w" "$BATS_TEST_TMPDIR/dox11.jsonl"
  [ "$status" -eq 2 ]
}

# ── dirt_unreachable_by_session: the two proofs, PER PATH (backlog ed54373d639b) ─────────────────
# The two terms above are all-or-nothing over DISJOINT populations, so a tree holding weeks-old dirt
# beside a peer's fresh WIP was cleared by neither (measured: session 62dcfa08, 25 files, blocked
# 3/3). Every CONTROL below is a way a per-path union could clear a path the session could have
# written — the under-conviction direction the item was filed to guard — and each is a real channel:
# the Bash window, an edit record, a subagent, a non-Bash tool, a detached command.

du() { # <repo> <session_id> <transcript>
  run bash -c ". '$LIB'; dirt_unreachable_by_session '$1' '$2' '$3'"
}

# The shared-checkout shape: old untracked dirt + a tracked file modified weeks ago + a peer's WIP
# written between two of this session's commands.
_du_mixed_tree() { # <tag> <fresh-mtime> → echoes the worktree
  local w; w="$(_po_clean_repo "$1")"
  echo a >> "$w/base.txt"; echo b > "$w/old-untracked.txt"; echo c > "$w/peer-wip.txt"
  _po_touch_at "$(( NOW - 7200 ))" "$w/base.txt"
  _po_touch_at "$(( NOW - 7200 ))" "$w/old-untracked.txt"
  _po_touch_at "$2" "$w/peer-wip.txt"
  printf '%s' "$w"
}

@test "DU1 the measured shape: old dirt + a peer's WIP in a gap ⇒ cleared, where neither proof alone can" {
  local w tr; w="$(_du_mixed_tree du1 "$(( NOW - 1800 ))")"
  tr="$(_po_tx_exec "$BATS_TEST_TMPDIR/du1.jsonl" "$(( NOW - 3600 ))" "$(( NOW - 10 ))" \
        --win "$(( NOW - 2400 ))" "$(( NOW - 2395 ))" --win "$(( NOW - 600 ))" "$(( NOW - 595 ))")"
  dps "$w" du-1 "$tr"; [ "$status" -eq 1 ]           # the peer's WIP refutes ordering
  dox "$w" "$tr";      [ "$status" -eq 2 ]           # the old dirt predates the bracket
  du  "$w" du-1 "$tr"
  [ "$status" -eq 0 ]
  [[ "$output" == paths=3,predates=2,gap=1,* ]] || false
}

# THE CONTROL THE ITEM LIVES OR DIES BY: the Bash-first session's OWN heredoc write. It has no edit
# record, so only its window can convict it — and the old dirt beside it must not dilute that.
@test "DU2 CONTROL: the fresh path stamped INSIDE a Bash window ⇒ refuted, own Bash dirt still convicts" {
  local w tr; w="$(_du_mixed_tree du2 "$(( NOW - 2398 ))")"
  tr="$(_po_tx_exec "$BATS_TEST_TMPDIR/du2.jsonl" "$(( NOW - 3600 ))" "$(( NOW - 10 ))" \
        --win "$(( NOW - 2400 ))" "$(( NOW - 2395 ))")"
  du "$w" du-2 "$tr"
  [ "$status" -eq 1 ]
}

# Positive self-evidence outranks ordering: an EDIT-RECORDED dirty path refutes even when its mtime
# reads as older than the session (a `cp -p` / `touch -t` stamp is exactly how that happens).
@test "DU3 CONTROL: an edit-recorded dirty path refutes even with a pre-session mtime" {
  local w tr; w="$(_du_mixed_tree du3 "$(( NOW - 1800 ))")"
  tr="$(_po_tx_exec "$BATS_TEST_TMPDIR/du3.jsonl" "$(( NOW - 3600 ))" "$(( NOW - 10 ))" \
        --edit "$w/old-untracked.txt" "$(( NOW - 3000 ))" "$(( NOW - 2999 ))")"
  du "$w" du-3 "$tr"
  [ "$status" -eq 1 ]
}

# The case dirt_outside_session_execution's clause (1) abstains on: a session that DID record an
# edit (to a file it has since committed) sitting beside a sibling's dirt. Valid here, because
# clause (a) answers for the edited paths directly.
@test "DU4 a session that recorded edits elsewhere + sibling dirt in a gap ⇒ cleared" {
  local w tr; w="$(_du_mixed_tree du4 "$(( NOW - 1800 ))")"
  tr="$(_po_tx_exec "$BATS_TEST_TMPDIR/du4.jsonl" "$(( NOW - 3600 ))" "$(( NOW - 10 ))" \
        --edit "$w/second.txt" "$(( NOW - 3000 ))" "$(( NOW - 2999 ))" \
        --win "$(( NOW - 2400 ))" "$(( NOW - 2395 ))")"
  dox "$w" "$tr"; [ "$status" -eq 2 ]
  du  "$w" du-4 "$tr"
  [ "$status" -eq 0 ]
}

# THE UNDER-CONVICTION completion-assert used to clear: one Edit (clean), then a SECOND file written
# with `sed -i` inside a window. session_dirty_mine reads rc 1 over it; this must not.
@test "DU5 CONTROL: a session with a clean Edit and a Bash-written dirty file ⇒ refuted" {
  local w tr; w="$(_po_clean_repo du5)"
  echo mine >> "$w/base.txt"
  _po_touch_at "$(( NOW - 2398 ))" "$w/base.txt"
  tr="$(_po_tx_exec "$BATS_TEST_TMPDIR/du5.jsonl" "$(( NOW - 3600 ))" "$(( NOW - 10 ))" \
        --edit "$w/second.txt" "$(( NOW - 3000 ))" "$(( NOW - 2999 ))" \
        --win "$(( NOW - 2400 ))" "$(( NOW - 2395 ))")"
  run bash -c ". '$SESSION_WRITES_LIB'; session_dirty_mine '$tr' '$w' >/dev/null 2>&1; echo \$?"
  [ "$output" = "1" ]                                  # the oracle's rc 1 — not an exoneration
  du "$w" du-5 "$tr"
  [ "$status" -eq 1 ]
}

# A subagent's records are in their own file; its `sed -i` runs while the MAIN chain sits in a gap.
@test "DU6 CONTROL: a SUBAGENT's Bash window covers the mtime ⇒ refuted" {
  local w tr; w="$(_po_clean_repo du6)"
  echo sub >> "$w/base.txt"
  _po_touch_at "$(( NOW - 1800 ))" "$w/base.txt"
  tr="$(_po_tx_exec "$BATS_TEST_TMPDIR/du6.jsonl" "$(( NOW - 3600 ))" "$(( NOW - 10 ))" \
        --tool Agent "$(( NOW - 2000 ))" "$(( NOW - 1990 ))" \
        --sub "$(( NOW - 1802 ))" "$(( NOW - 1798 ))")"
  du "$w" du-6 "$tr"
  [ "$status" -eq 1 ]
}

@test "DU7 CONTROL: a SUBAGENT's Edit of the dirty path ⇒ refuted (the edit set reads subagent files)" {
  local w tr; w="$(_po_clean_repo du7)"
  echo sub >> "$w/base.txt"
  _po_touch_at "$(( NOW - 7200 ))" "$w/base.txt"
  tr="$(_po_tx_exec "$BATS_TEST_TMPDIR/du7.jsonl" "$(( NOW - 3600 ))" "$(( NOW - 10 ))" \
        --subedit "$w/base.txt" "$(( NOW - 1802 ))" "$(( NOW - 1798 ))")"
  du "$w" du-7 "$tr"
  [ "$status" -eq 1 ]
}

# A background subagent's own windows are what bound it, so the FLAG on its Agent call is not
# treated as detached — otherwise every session that ever delegated could never be cleared.
@test "DU8 a backgrounded Agent call does not disable the proof; its subagent's windows do the bounding" {
  local w tr; w="$(_du_mixed_tree du8 "$(( NOW - 1800 ))")"
  tr="$(_po_tx_exec "$BATS_TEST_TMPDIR/du8.jsonl" "$(( NOW - 3600 ))" "$(( NOW - 10 ))" \
        --tool Agent-bg "$(( NOW - 2000 ))" "$(( NOW - 1999 ))" \
        --sub "$(( NOW - 1500 ))" "$(( NOW - 1490 ))")"
  du "$w" du-8 "$tr"
  [ "$status" -eq 0 ]
}

# Bash is the channel with no edit record, not the only one with side effects.
@test "DU9 CONTROL: a non-Bash tool's window covers the mtime ⇒ refuted" {
  local w tr; w="$(_du_mixed_tree du9 "$(( NOW - 1800 ))")"
  tr="$(_po_tx_exec "$BATS_TEST_TMPDIR/du9.jsonl" "$(( NOW - 3600 ))" "$(( NOW - 10 ))" \
        --tool mcp__ms365__download-bytes-to-file "$(( NOW - 1801 ))" "$(( NOW - 1799 ))")"
  du "$w" du-9 "$tr"
  [ "$status" -eq 1 ]
}

# Monitor runs its command in the background, so its effects outlive every window it has.
@test "DU10 CONTROL: a Monitor call anywhere ⇒ a gap path is cannot-tell" {
  local w tr; w="$(_du_mixed_tree du10 "$(( NOW - 1800 ))")"
  tr="$(_po_tx_exec "$BATS_TEST_TMPDIR/du10.jsonl" "$(( NOW - 3600 ))" "$(( NOW - 10 ))" \
        --tool Monitor "$(( NOW - 3000 ))" "$(( NOW - 2999 ))")"
  du "$w" du-10 "$tr"
  [ "$status" -eq 2 ]
}

# …and ordering is untouched by it: a command this session ran cannot predate the session.
@test "DU11 a Monitor call does not stop the ORDERING half: all-predating dirt still clears" {
  local w tr; w="$(_po_clean_repo du11)"
  echo a >> "$w/base.txt"
  _po_touch_at "$(( NOW - 7200 ))" "$w/base.txt"
  tr="$(_po_tx_exec "$BATS_TEST_TMPDIR/du11.jsonl" "$(( NOW - 3600 ))" "$(( NOW - 10 ))" \
        --tool Monitor "$(( NOW - 3000 ))" "$(( NOW - 2999 ))")"
  du "$w" du-11 "$tr"
  [ "$status" -eq 0 ]
  [[ "$output" == paths=1,predates=1,gap=0,* ]] || false
}

@test "DU12 CONTROL: a path stamped after the last record ⇒ cannot-tell, whatever else clears" {
  local w tr; w="$(_du_mixed_tree du12 "$(( NOW - 5 ))")"
  tr="$(_po_tx_exec "$BATS_TEST_TMPDIR/du12.jsonl" "$(( NOW - 3600 ))" "$(( NOW - 600 ))" \
        --win "$(( NOW - 2400 ))" "$(( NOW - 2395 ))")"
  du "$w" du-12 "$tr"
  [ "$status" -eq 2 ]
}

# A deletion has no mtime; the cleared paths beside it are what make this non-vacuous.
@test "DU13 CONTROL: a deletion beside cleared paths ⇒ cannot-tell" {
  local w tr; w="$(_du_mixed_tree du13 "$(( NOW - 1800 ))")"
  git -C "$w" checkout -q -- base.txt; rm -f "$w/second.txt"
  tr="$(_po_tx_exec "$BATS_TEST_TMPDIR/du13.jsonl" "$(( NOW - 3600 ))" "$(( NOW - 10 ))" \
        --win "$(( NOW - 2400 ))" "$(( NOW - 2395 ))")"
  du "$w" du-13 "$tr"
  [ "$status" -eq 2 ]
}

# The bracket is what the MAIN transcript testifies about. A subagent record stamped later must not
# stretch it over dirt the main file cannot speak for.
@test "DU15 CONTROL: a later SUBAGENT record does not widen the bracket" {
  local w tr; w="$(_po_clean_repo du15)"
  echo x >> "$w/base.txt"
  _po_touch_at "$(( NOW - 300 ))" "$w/base.txt"
  tr="$(_po_tx_exec "$BATS_TEST_TMPDIR/du15.jsonl" "$(( NOW - 3600 ))" "$(( NOW - 600 ))" \
        --sub "$(( NOW - 100 ))" "$(( NOW - 90 ))")"
  du "$w" du-15 "$tr"
  [ "$status" -eq 2 ]
}

@test "DU14 CONTROL: a CLEAN tree ⇒ cannot-tell, not an exoneration" {
  local w tr; w="$(_po_clean_repo du14)"
  tr="$(_po_tx_exec "$BATS_TEST_TMPDIR/du14.jsonl" "$(( NOW - 3600 ))" "$(( NOW - 10 ))")"
  du "$w" du-14 "$tr"
  [ "$status" -eq 2 ]
}
