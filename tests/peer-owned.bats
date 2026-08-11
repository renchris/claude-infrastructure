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
