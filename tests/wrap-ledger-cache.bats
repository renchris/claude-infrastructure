#!/usr/bin/env bats
# wrap-ledger-cache.bats — the --machine memo (Wave B / §S6.4).
#
# WHAT IS AT STAKE. This memo sits under the close protocol: six Stop hooks read `--machine` on one
# event, and a stale serve here is a rung the model then asserts to the operator. So the suite is
# built around ONE question — can the cache ever answer differently from a fresh computation? —
# and every positive test below is paired with a MUTATION that makes it fail.
#
# Harness laws (repo convention): L1 fixtures reproduce the LIVE shape; L2 assertions key on
# failure-distinct values; L3 `[ ]` / `grep -q` only; L4 every behaviour has a must-change AND a
# must-NOT-change fixture.

setup() {
  # HERMETICITY first — the subject resolves its cache dir and its rung stores under $HOME.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  S="$REPO/scripts/wrap-ledger.sh"
  D="$BATS_TEST_TMPDIR"
  export WRAP_CACHE_DIR="$D/cache"

  # A real git repo, because the subject's first act is `rev-parse --is-inside-work-tree` and a
  # fixture that faked it would exercise a code path production never takes.
  FIX="$D/repo"; mkdir -p "$FIX"
  git -C "$FIX" init -q 2>/dev/null
  git -C "$FIX" config user.email t@t.invalid
  git -C "$FIX" config user.name t
  printf 'seed\n' > "$FIX/f.txt"
  git -C "$FIX" add f.txt
  git -C "$FIX" commit -qm seed 2>/dev/null
  cd "$FIX" || return 1
}

# A counting shim on PATH. `git` is resolved by NAME here deliberately: that is how the subject
# invokes it, so a shim earlier on PATH counts exactly the subprocesses production would fork.
mkshim() {
  SHIM="$D/shim"; mkdir -p "$SHIM"
  REALGIT="$(command -v git)"
  cat > "$SHIM/git" <<EOF
#!/bin/bash
echo "\$*" >> "$SHIM/calls.log"
exec "$REALGIT" "\$@"
EOF
  chmod +x "$SHIM/git"
  : > "$SHIM/calls.log"
}
gitcalls() { wc -l < "$SHIM/calls.log" | tr -d ' '; }
runshim() { : > "$SHIM/calls.log"; PATH="$SHIM:$PATH" bash "$S" --machine >/dev/null 2>&1; }

# ══ §A — PARITY: the cache must never change the answer ══

@test "A1: WRAP_CACHE=off, a cache MISS and a cache HIT all emit byte-identical output" {
  off="$(WRAP_CACHE=off bash "$S" --machine)"
  miss="$(bash "$S" --machine)"
  hit="$(bash "$S" --machine)"
  [ "$off" = "$miss" ]
  [ "$miss" = "$hit" ]
  printf '%s' "$hit" | grep -q '^RUNG='
}

@test "A2: a HIT is served from disk — the cache file exists and carries the whole record" {
  bash "$S" --machine >/dev/null
  [ -d "$WRAP_CACHE_DIR" ]
  n="$(find "$WRAP_CACHE_DIR" -name '*.machine' | wc -l | tr -d ' ')"
  [ "$n" -eq 1 ]
  f="$(find "$WRAP_CACHE_DIR" -name '*.machine' | head -1)"
  grep -q '^RUNG=' "$f"
}

@test "A3: WRAP_CACHE=off neither reads nor writes the cache" {
  WRAP_CACHE=off bash "$S" --machine >/dev/null
  n="$(find "$WRAP_CACHE_DIR" -name '*.machine' 2>/dev/null | wc -l | tr -d ' ')"
  [ "$n" -eq 0 ]
}

# ══ §B — THE SAVING: a hit must actually skip the work ══

@test "B1: a HIT forks strictly fewer git subprocesses than an uncached run" {
  mkshim
  : > "$SHIM/calls.log"; PATH="$SHIM:$PATH" WRAP_CACHE=off bash "$S" --machine >/dev/null 2>&1
  off="$(gitcalls)"
  runshim                       # miss: computes and writes
  runshim                       # hit
  hit="$(gitcalls)"
  # L2: key on the failure-distinct direction, not on an exact count. An exact count would red on
  # the subject's own growth without ever catching a regression (MEMORY.md
  # exact-count-assertion-tripwires-its-own-subject).
  [ "$hit" -lt "$off" ]
  [ "$off" -ge 5 ]
}

# ══ §C — INVALIDATION: every input a rung turns on must move the key ══

@test "C1: a new untracked file invalidates — the dirty rung is recomputed, never served stale" {
  clean="$(bash "$S" --machine)"
  printf '%s' "$clean" | grep -q '^DIRTY=0'
  printf 'new\n' > "$FIX/untracked.txt"
  dirty="$(bash "$S" --machine)"
  printf '%s' "$dirty" | grep -q '^DIRTY=1'
}

@test "C2: a new COMMIT invalidates — HEAD is part of the key" {
  bash "$S" --machine >/dev/null
  before="$(find "$WRAP_CACHE_DIR" -name '*.machine' | wc -l | tr -d ' ')"
  printf 'more\n' >> "$FIX/f.txt"
  git -C "$FIX" commit -qam more 2>/dev/null
  bash "$S" --machine >/dev/null
  after="$(find "$WRAP_CACHE_DIR" -name '*.machine' | wc -l | tr -d ' ')"
  # A second key, not an overwritten one — proof the fingerprint moved rather than the file merely
  # being rewritten under the same name.
  [ "$after" -gt "$before" ]
}

@test "C3: the TTL is a SECOND bound — a 0 s TTL never serves a hit" {
  mkshim
  runshim
  : > "$SHIM/calls.log"; PATH="$SHIM:$PATH" WRAP_CACHE_TTL_S=0 bash "$S" --machine >/dev/null 2>&1
  ttl0="$(gitcalls)"
  runshim
  hit="$(gitcalls)"
  [ "$ttl0" -gt "$hit" ]
}

# ══ §D — LOUD DEGRADATION: a broken cache is a SLOW ledger, never a wrong one ══

@test "D1: a truncated cache file is NOT served" {
  bash "$S" --machine >/dev/null
  f="$(find "$WRAP_CACHE_DIR" -name '*.machine' | head -1)"
  printf 'RUN' > "$f"                      # no RUNG= line: a partial write
  out="$(bash "$S" --machine)"
  printf '%s' "$out" | grep -q '^RUNG='
  [ "$(printf '%s' "$out" | wc -l | tr -d ' ')" -gt 3 ]
}

@test "D2: an EMPTY cache file is NOT served" {
  bash "$S" --machine >/dev/null
  f="$(find "$WRAP_CACHE_DIR" -name '*.machine' | head -1)"
  : > "$f"
  out="$(bash "$S" --machine)"
  printf '%s' "$out" | grep -q '^RUNG='
}

@test "D3: an unwritable cache dir still emits a correct ledger" {
  mkdir -p "$D/ro"; chmod 500 "$D/ro"
  out="$(WRAP_CACHE_DIR="$D/ro/sub" bash "$S" --machine)"
  chmod 700 "$D/ro" || true
  printf '%s' "$out" | grep -q '^RUNG='
  ref="$(WRAP_CACHE=off bash "$S" --machine)"
  [ "$out" = "$ref" ]
}

@test "D4: outside a git work tree the memo is bypassed and the not-a-repo contract survives" {
  mkdir -p "$D/notrepo"; cd "$D/notrepo" || return 1
  run bash "$S" --machine
  [ "$status" -eq 3 ]
  printf '%s' "$output" | grep -q 'ERROR=not-a-git-repo'
}

# ══ §E — MUTATION CHECKS. Each neuters ONE behaviour in a COPY of the real file and asserts a
#         positive test above flips, so none of the above can be passing vacuously.

@test "E1: MUTATION — dropping the porcelain digest from the key serves a STALE dirty rung" {
  m="$D/mut1.sh"
  sed 's@^  status_digest=.*@  status_digest=CONSTANT@' "$S" > "$m"
  chmod +x "$m"
  # The mutation must actually have applied — a no-op sed would pass this test vacuously.
  grep -q 'status_digest=CONSTANT' "$m"
  ! grep -q 'status_digest="$(git status --porcelain' "$m" || false

  clean="$(bash "$m" --machine)"
  printf '%s' "$clean" | grep -q '^DIRTY=0'
  printf 'new\n' > "$FIX/untracked.txt"
  after="$(bash "$m" --machine)"
  # With the digest gone the key cannot move, so the clean ledger is served over a dirty tree.
  if printf '%s' "$after" | grep -q '^DIRTY=1'; then
    echo "MUTATION SURVIVED: porcelain digest removed from the key but the dirty tree still invalidated" >&2
    false
  fi
  printf '%s' "$after" | grep -q '^DIRTY=0'
}

@test "E2: MUTATION — dropping the wholeness check serves a truncated cache file" {
  m="$D/mut2.sh"
  sed "s|if grep -q '\^RUNG=' \"\$CACHE_FILE\" 2>/dev/null; then|if true; then|" "$S" > "$m"
  chmod +x "$m"
  grep -q 'if true; then' "$m"

  bash "$m" --machine >/dev/null
  f="$(find "$WRAP_CACHE_DIR" -name '*.machine' | head -1)"
  printf 'RUN' > "$f"
  out="$(bash "$m" --machine)"
  # The fragment is now served verbatim — exactly the defect D1 pins.
  if printf '%s' "$out" | grep -q '^RUNG='; then
    echo "MUTATION SURVIVED: wholeness check removed but a truncated file was still rejected" >&2
    false
  fi
  [ "$out" = "RUN" ]
}

@test "E3: MUTATION — a cache keyed without \$PWD serves one repo's ledger for another" {
  m="$D/mut3.sh"
  sed 's|"$head" "$status_digest" "$stores" "$PWD" "${SESSION_FLAG:-}" "${WRAP_TRUNK:-}"|"$head" "$status_digest" "$stores" "" "${SESSION_FLAG:-}" "${WRAP_TRUNK:-}"|' "$S" > "$m"
  chmod +x "$m"
  grep -q '"$stores" ""' "$m"

  # Two repos identical by CONSTRUCTION — a byte copy of the tree, so the same HEAD, the same
  # porcelain and the same stores. $PWD is then the only term that differs, which is exactly the
  # term the mutation deletes. (An amend cannot reproduce a sha, so the first version of this
  # fixture could only ever skip — a control that never runs proves nothing.)
  B="$D/repo2"
  cp -R "$FIX" "$B"
  a="$(git -C "$FIX" rev-parse HEAD)"; b="$(git -C "$B" rev-parse HEAD)"
  [ "$a" = "$b" ]

  bash "$m" --machine >/dev/null
  n1="$(find "$WRAP_CACHE_DIR" -name '*.machine' | wc -l | tr -d ' ')"
  cd "$B" || return 1
  bash "$m" --machine >/dev/null
  n2="$(find "$WRAP_CACHE_DIR" -name '*.machine' | wc -l | tr -d ' ')"
  if [ "$n2" -gt "$n1" ]; then
    echo "MUTATION SURVIVED: \$PWD removed from the key but the second repo still minted its own entry" >&2
    false
  fi
  [ "$n2" -eq "$n1" ]
}

# ══ §F — SINGLE-FLIGHT. Without it the memo is a measured REGRESSION, not a saving. ══
#
# The six consumers are dispatched CONCURRENTLY, not one after another. Cold, all six miss together
# and the fingerprints become pure added cost: measured 72 git subprocesses against 60 with the
# cache off. The sequential figure was real and measured the wrong arrival pattern.

conc6() { # <label-of-env> — six concurrent --machine runs, returns the git subprocess count
  : > "$SHIM/calls.log"
  local i
  for i in 1 2 3 4 5 6; do
    PATH="$SHIM:$PATH" env "$@" bash "$S" --machine >/dev/null 2>&1 &
  done
  wait
  gitcalls
}

@test "F1: six CONCURRENT consumers cost strictly less than six uncached — no stampede" {
  mkshim
  off="$(conc6 WRAP_CACHE=off)"
  cold="$(conc6 WRAP_CACHE_DIR=$WRAP_CACHE_DIR)"
  # The cold concurrent case is the one that regressed before single-flight. It must be a saving,
  # not merely "no worse" — a cache that breaks even on its own hot path is not worth its risk.
  [ "$cold" -lt "$off" ]
  [ "$off" -ge 30 ]
}

@test "F2: six concurrent consumers leave NO lock behind" {
  mkshim
  conc6 WRAP_CACHE_DIR="$WRAP_CACHE_DIR" >/dev/null
  n="$(find "$WRAP_CACHE_DIR" -name '*.lock' -type d 2>/dev/null | wc -l | tr -d ' ')"
  [ "$n" -eq 0 ]
}

@test "F3: a STALE lock is cleared, not waited behind" {
  # A winner that died mid-compute must cost one stale window, never wedge every later close.
  bash "$S" --machine >/dev/null            # mint the key so the lock path is predictable
  f="$(find "$WRAP_CACHE_DIR" -name '*.machine' | head -1)"
  : > "$f"                                   # force a miss without changing the key
  mkdir -p "$f.lock"
  touch -t 202001010000 "$f.lock"
  run bash "$S" --machine
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '^RUNG='
  ! [ -d "$f.lock" ] || false
}

@test "F4: MUTATION — removing single-flight makes the concurrent cold path REGRESS" {
  m="$D/mut4.sh"
  # Neuter the lock acquisition so every concurrent caller believes it is the winner, which is the
  # pre-single-flight behaviour exactly.
  sed 's|if mkdir "$LOCK" 2>/dev/null; then|if true; then|' "$S" > "$m"
  chmod +x "$m"
  grep -q 'if true; then' "$m"

  mkshim
  : > "$SHIM/calls.log"
  for i in 1 2 3 4 5 6; do PATH="$SHIM:$PATH" WRAP_CACHE=off bash "$m" --machine >/dev/null 2>&1 & done
  wait
  off="$(gitcalls)"
  : > "$SHIM/calls.log"
  for i in 1 2 3 4 5 6; do PATH="$SHIM:$PATH" bash "$m" --machine >/dev/null 2>&1 & done
  wait
  cold="$(gitcalls)"
  # Without the lock the memo costs MORE than no memo at all: six fingerprints on top of six
  # full computations. If this still comes out cheaper, F1 proves nothing.
  if [ "$cold" -lt "$off" ]; then
    echo "MUTATION SURVIVED: single-flight removed but the concurrent cold path was still cheaper ($cold < $off)" >&2
    false
  fi
  [ "$cold" -ge "$off" ]
}
