#!/usr/bin/env bats
# cc-jetsam-exec — the kernel-backstop arm for the dev-worker class.
#
# WHAT THIS SUITE HAS TO PROVE, and why each is a case rather than a comment:
#   · THAT THE LEVER IS REAL. The whole tool rests on one claim about this kernel:
#     posix_spawnattr_setjetsam_ext(3) is enforced for an UNPRIVILEGED caller. If that is false the
#     tool is a no-op that prints verdict=protected forever — the exact fail-safe-mimics-healthy
#     shape this repo has already eaten. §A asserts the kill.
#   · THE CONTROL ARM. A case that only shows "wrapped ⇒ killed" cannot distinguish the stamp from
#     a child that was going to die anyway. §A therefore runs the IDENTICAL command unwrapped and
#     requires it to survive. One variable, both arms.
#   · THE GRANDCHILD, AND A MUTANT FOR IT. The stamp is NOT inherited (measured: neither fork() nor
#     exec children get it), which is why the tool interposes posix_spawn rather than just stamping
#     the command. §B proves a grandchild IS reached — and then runs the same tree with the
#     interposer removed from DYLD_INSERT_LIBRARIES and requires it to SURVIVE. Without that mutant
#     §B would be credited to the launcher, which stamps only the top process, and the interposer —
#     the entire reason this tool is not a two-line wrapper — would be untested.
#   · FAIL-CLOSED. §C requires that a tool which cannot build its helper REFUSES rather than
#     running the lane uncapped. A guard that degrades into "ran the command" is indistinguishable
#     from one that worked.
#   · THE CACHE KEY. §D requires the key to be refused when degenerate. An empty key is not a narrow
#     cache directory, it is a SHARED one, and two source versions would silently reuse one helper.
#   · THE SHELL BOUNDARY, structurally. /bin/sh and /bin/zsh are SIP-restricted: dyld purges
#     DYLD_INSERT_LIBRARIES, so every worker below such a shell silently loses the stamp. §E pins
#     that the tool execs its target directly, because the defect it prevents is invisible at run
#     time — the lane still works, it is just unprotected.
#
# PROOF DISCIPLINE: every case builds its own fixtures under $BATS_TEST_TMPDIR and points the
# helper cache there, so no run touches the operator's real ~/.cache/cc-jetsam.

bats_require_minimum_version 1.5.0   # `run -127` (exit-status-checked run)

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  T="$REPO/bin/cc-jetsam-exec"
  D="$BATS_TEST_TMPDIR"
  # FIXTURED $HOME: the subject's default helper cache is $XDG_CACHE_HOME/cc-jetsam, which falls
  # back to ~/.cache — an unfixtured run would build into the operator's live cache and, worse,
  # would share it between concurrent runs of this suite.
  export HOME="$D/home"; mkdir -p "$HOME"
  export CC_JETSAM_CACHE="$D/cache"
  [ -x "$T" ] || false

  CC_BIN="$(command -v clang || command -v cc || true)"
  if [ -z "$CC_BIN" ]; then skip "no C compiler — the subject cannot build its helper here either"; fi

  # HOG: touches N MiB of real pages. phys_footprint is what a jetsam memlimit meters, so the
  # pages must be WRITTEN — a malloc that is never touched costs no footprint and would make every
  # case below pass vacuously.
  cat > "$D/hog.c" <<'CSRC'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc, char **argv){
  int mb = argc>1 ? atoi(argv[1]) : 200;
  for (int i=0;i<mb;i++){ char *p = malloc(1<<20); if(!p) return 2; memset(p, i&0xff, 1<<20); }
  printf("SURVIVED %d\n", mb); fflush(stdout); return 0;
}
CSRC
  "$CC_BIN" -O0 -o "$D/hog" "$D/hog.c" 2>/dev/null || false

  # RELAY: spawns hog as an ordinary child and reports how it died. This is the storm's own shape —
  # one parent, holders below it — and the only thing that can exercise the interposer.
  cat > "$D/relay.c" <<'CSRC'
#include <stdio.h>
#include <stdlib.h>
#include <spawn.h>
#include <unistd.h>
#include <sys/wait.h>
extern char **environ;
int main(int argc, char **argv){
  pid_t pid; char *a[] = { argv[1], argv[2], NULL };
  if (posix_spawn(&pid, argv[1], NULL, NULL, a, environ) != 0) return 127;
  int st=0; waitpid(pid,&st,0);
  if (WIFSIGNALED(st)) { printf("GRANDCHILD_SIGNALED %d\n", WTERMSIG(st)); return 0; }
  printf("GRANDCHILD_EXITED %d\n", WIFEXITED(st) ? WEXITSTATUS(st) : -1);
  return 0;
}
CSRC
  "$CC_BIN" -O0 -o "$D/relay" "$D/relay.c" 2>/dev/null || false

  MEMCAP=60      # the stamp
  TOUCH=200      # comfortably past it, and small enough to be cheap
}

# ── §A the lever itself, with its control ────────────────────────────────────────────────────────

@test "A1 a fatal memlimit kills the wrapped command at the limit" {
  run "$T" --mem "$MEMCAP" --fatal -- "$D/hog" "$TOUCH"
  [ "$status" -eq 137 ]                      # 128 + SIGKILL
  [[ "$output" != *"SURVIVED"* ]]
}

@test "A2 CONTROL — the identical command unwrapped survives the same allocation" {
  run "$D/hog" "$TOUCH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SURVIVED $TOUCH"* ]]
}

@test "A3 the default limit is SOFT — a high-water mark, not a kill, with no system pressure" {
  run "$T" --mem "$MEMCAP" -- "$D/hog" "$TOUCH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SURVIVED $TOUCH"* ]] || false
  [[ "$output" == *"verdict=protected"* ]] || false
  [[ "$output" == *"mode=soft"* ]]
}

# ── §B the grandchild — the reason the tool interposes rather than wraps ──────────────────────────

@test "B1 the stamp reaches a GRANDCHILD the wrapper never spawned" {
  run "$T" --mem "$MEMCAP" --fatal -- "$D/relay" "$D/hog" "$TOUCH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"GRANDCHILD_SIGNALED 9"* ]]
}

@test "B2 MUTANT — with the interposer removed, the same grandchild survives" {
  # Proves B1 credits the INTERPOSER and not the launcher: the launcher stamps only the process it
  # spawns, so with the dylib gone the relay is capped and its child is not.
  run "$T" --mem "$MEMCAP" --fatal -- "$D/relay" "$D/hog" "$TOUCH"
  [ "$status" -eq 0 ]
  local cache_dir
  cache_dir="$(printf '%s\n' "$output" | sed -n 's/.*helper=\(.*\)$/\1/p' | tail -1)"
  [ -x "$cache_dir/cc-jetsam-launch" ]
  run env CC_JETSAM_MEMLIMIT_MB="$MEMCAP" CC_JETSAM_FATAL=1 CC_JETSAM_BAND=30 \
      "$cache_dir/cc-jetsam-launch" "$D/relay" "$D/hog" "$TOUCH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"GRANDCHILD_EXITED 0"* ]]
}

@test "B3 the exclusion backstop leaves a named basename unstamped" {
  cp "$D/hog" "$D/claude"
  run env CC_JETSAM_EXCLUDE=claude "$T" --mem "$MEMCAP" --fatal -- "$D/claude" "$TOUCH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SURVIVED $TOUCH"* ]]
}

# ── §C fail-closed ───────────────────────────────────────────────────────────────────────────────

@test "C1 with no compiler reachable the tool REFUSES and the command does not run" {
  export CC_JETSAM_CACHE="$D/cache-nocc"
  run env PATH="/usr/bin:/bin:/usr/sbin:/sbin" CC_JETSAM_CACHE="$D/cache-nocc" \
      CC="" bash "$T" --mem "$MEMCAP" -- "$D/hog" 1
  # /usr/bin/cc exists on a box with the CLT, so force the failure through an unbuildable cache dir
  # instead when it does: either way the contract is the same — refuse, and do not run the command.
  if [ "$status" -eq 0 ]; then
    run env CC_JETSAM_CACHE="/dev/null/unwritable" bash "$T" --mem "$MEMCAP" -- "$D/hog" 1
  fi
  [ "$status" -ne 0 ]
  [[ "$output" == *"verdict=unprotected"* ]] || false
  [[ "$output" != *"SURVIVED"* ]]
}

@test "C2 --allow-unprotected runs the lane and SAYS so" {
  run env CC_JETSAM_CACHE="/dev/null/unwritable" bash "$T" --mem "$MEMCAP" --allow-unprotected -- "$D/hog" 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=unprotected"* ]] || false
  [[ "$output" == *"SURVIVED 1"* ]]
}

@test "C3 a cap nobody chose is refused — --mem is required" {
  run "$T" -- "$D/hog" 1
  [ "$status" -eq 2 ]
  [[ "$output" != *"SURVIVED"* ]]
}

@test "C4 a band above the default band is refused" {
  run "$T" --mem "$MEMCAP" --band 200 -- "$D/hog" 1
  [ "$status" -eq 2 ]
  [[ "$output" != *"SURVIVED"* ]]
}

# ── §D the helper cache key ──────────────────────────────────────────────────────────────────────

@test "D1 the cache key is keyed on the embedded source, so a source edit cannot reuse a helper" {
  run "$T" --mem "$MEMCAP" -- "$D/hog" 1
  [ "$status" -eq 0 ]
  local k1; k1="$(printf '%s\n' "$output" | sed -n 's/.*helper=.*\/\([0-9a-f]*-[a-z0-9_]*\)$/\1/p' | tail -1)"
  [[ "$k1" =~ ^[0-9a-f]{16}- ]] || false
  # the same source must produce the same key (the cache is reused, not rebuilt per invocation)
  run "$T" --mem "$MEMCAP" -- "$D/hog" 1
  local k2; k2="$(printf '%s\n' "$output" | sed -n 's/.*helper=.*\/\([0-9a-f]*-[a-z0-9_]*\)$/\1/p' | tail -1)"
  [ "$k1" = "$k2" ]
}

# ── §E the structural pins ───────────────────────────────────────────────────────────────────────

@test "E1 the tool never runs its target through a system shell (dyld purges the stamp there)" {
  # /bin/sh and /bin/zsh are SIP-restricted: DYLD_INSERT_LIBRARIES is both ignored AND purged, so a
  # `sh -c` in this position would drop protection for every worker below it while still succeeding.
  run grep -nE '^[^#]*(exec|run)[^#]*\b(sh|zsh|bash)[[:space:]]+-c\b' "$T"
  [ "$status" -ne 0 ]
}

@test "E2 the helper source is EMBEDDED, so no sibling is resolved against a symlink's directory" {
  # This file is deployed as a per-file symlink into ~/.claude/bin; a $0-relative sibling read would
  # resolve there and silently find nothing.
  run grep -c 'CSRC' "$T"
  [ "$status" -eq 0 ]
  run bash -c "grep -nE 'dirname .\\\$0|BASH_SOURCE' '$T' | grep -v '^\\s*#'"
  [ "$status" -ne 0 ]
}

@test "E3 exit disposition is reproduced, not invented" {
  run "$T" --mem 4096 -- /usr/bin/false
  [ "$status" -eq 1 ]
  run "$T" --mem 4096 -- /usr/bin/true
  [ "$status" -eq 0 ]
  run -127 "$T" --mem 4096 -- "$D/no-such-binary"
}

@test "C5 a corrupt cached helper is rebuilt, never handed to dyld (which ABORTS, not warns)" {
  # Measured 2026-09-10: DYLD_INSERT_LIBRARIES naming an unloadable dylib terminates the process at
  # exec with SIGABRT (exit 134) and a message naming dyld, not this tool. A cache directory pruned
  # or truncated by any tmp-reaper would therefore kill the wrapped lane outright. The smoke-test
  # this pins is what makes that this tool's own refusal instead.
  run "$T" --mem "$MEMCAP" --fatal -- "$D/hog" "$TOUCH"
  [ "$status" -eq 137 ]
  local cache_dir
  cache_dir="$(printf '%s\n' "$output" | sed -n 's/.*helper=\(.*\)$/\1/p' | tail -1)"
  [ -f "$cache_dir/libcc-jetsam-interpose.dylib" ]
  printf 'not a mach-o file' > "$cache_dir/libcc-jetsam-interpose.dylib"
  run "$T" --mem "$MEMCAP" --fatal -- "$D/hog" "$TOUCH"
  [ "$status" -eq 137 ]                     # rebuilt and still enforcing …
  [ "$status" -ne 134 ]                     # … and never the dyld abort
}
