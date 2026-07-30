#!/bin/bash
# bats-shim-parity-lint — make the ONE brew-upgrade-fragile step of row 13's "shadow mode" LOUD.
#
# WHY THIS EXISTS (row 13, MACHINE_CAPACITY_V2.md §9.4). The `bats` QoS shim (`bin/cc-bats`) is
# installed at ~/.claude/bin/bats, position 1 on PATH, so every PATH-resolved invocation lands in
# Darwin's BACKGROUND band. Measured after activation (2026-07-29 18:01), that is NOT enough:
#
#     ~6 absolute-path vs ~14 PATH-based live top-level invocations  ⇒  ~30% structurally uncovered
#     one post-shim run persisted at pri=31 across four samples:
#         timeout 90 /opt/homebrew/bin/bats tests/handoff-fire-validate.bats
#
# An absolute-path invocation never consults PATH, so a PATH shim cannot see it. §9.4 option 1 —
# "shadow mode" — closes that by ALSO repointing /opt/homebrew/bin/bats at cc-bats. It is an
# operator-owned activation (it mutates a package-manager-owned path machine-wide), and it has one
# named failure mode:
#
#     `brew upgrade bats-core` SILENTLY restores Homebrew's own symlink.
#
# Nothing breaks when that happens. Every gate still runs, every test still passes, and ~30% of
# invocations quietly go back to full interactive priority. That is the exact shape of the defect
# row 13 exists to remove — a mechanism that LOOKS applied and is not (feature-durability:
# an enforced mechanism must FAIL LOUD when inert). This lint is that loud failure.
#
# THE ACTIVATION MARKER IS THE SEED FILE'S EXISTENCE. bin/cc-bats:58-65 records the absolute path of
# the REAL bats — read from disk truth at activation time, never guessed from a version-shaped Cellar
# glob — at $HOME/.claude/state/cc-bats-real. No seed ⇒ shadow mode was never
# activated ⇒ /opt/homebrew/bin/bats pointing at Homebrew's own binary is CORRECT and this lint must
# say so plainly. A lint that cries wolf on the healthy default gets disabled, and then it is worth
# zero on the day it matters.
#
# FOUR STATES, NEVER A BOOLEAN — "cannot tell" must never read as "fine" (the repo's standing
# gate-never-ran-vs-gate-red rule, and §9.3's own catch: a boolean would have said "fine" while a
# heredoc ate the data channel):
#
#   NOT-ACTIVE  0   no seed — shadow mode is not in use. HEALTHY, not a warning.
#   OK          0   seed present, shim still installed, seeded real bats present+executable.
#   DRIFT       1   seed present but /opt/homebrew/bin/bats NO LONGER resolves to cc-bats.
#                   THIS IS THE WHOLE POINT: brew restored it and 30% of invocations are uncovered.
#   STALE-SEED  2   seed present, shim installed, but the seeded target is gone/non-executable —
#                   brew upgraded the Cellar out from under the recording. cc-bats degrades to its
#                   guessing resolver (bin/cc-bats:106-118), so this is MEASURED FALSE in review: with two shims on PATH a stale seed did NOT reach the Cellar sweep — the PATH walk returned the SIBLING SHIM and the run became a non-terminating 2-cycle (rc=137, zero output). Treat STALE-SEED as serious, not cosmetic..
#   NO-DATA     3   cannot read what it needs to judge. A NON-VERDICT, never a pass.
#   DISABLED    0   kill switch — reported as its own state so "turned off" can never be misread as
#                   NOT-ACTIVE (which is a real judgement about the machine).
#   usage      64   unknown argument (EX_USAGE) — a flag typo must never be silently ignored.
#
# PHYSICAL-PATH COMPARISON, not string equality. Both sides are fully symlink-resolved and their
# directories physicalised (`cd … && pwd -P`) before comparing: shadow mode installs a symlink
# CHAIN (/opt/homebrew/bin/bats → ~/.claude/bin/bats → <checkout>/bin/cc-bats), and this checkout is
# itself reached through symlinked parents. String equality would report DRIFT on a correct install.
#
# READ-ONLY BY CONSTRUCTION. This file contains no mkdir, no redirection into any judged path, no
# ln, no rm. It reads and reports; repointing a Homebrew-owned symlink is the operator's call and is
# printed as an exact command, never executed here (tests assert the read-only property directly).
#
# Env seams — each honoured VERBATIM including SET-BUT-EMPTY (`${VAR+set}`, never `${VAR:-}`; a seam
# that cannot express "empty" cannot turn a thing off, and the three states unset/empty/set are what
# the tests need to prove no hidden fallback):
#   CC_BATS_SEED        seed path       (default $HOME/.claude/state/cc-bats-real)
#   CC_BATS_SHIM_PATH   judged path     (default /opt/homebrew/bin/bats)
#   CC_BATS_EXPECT      what it must resolve to (default <repo>/bin/cc-bats, relative to THIS script)
#   CC_BATS_PARITY_LINT =off ⇒ DISABLED, exit 0
#
# OBSOLETE NOTE (kept for history) — the asymmetry is GONE: vs the shim: bin/cc-bats:65 reads its seam with `${CC_BATS_SEED:-…}`,
# so a set-but-EMPTY CC_BATS_SEED falls back to the default THERE and is honoured verbatim HERE.
# Stated rather than hidden. It cannot affect a real judgement — nothing sets that variable empty in
# production — and the `+set` form is what makes the lint's own no-fallback behaviour testable.
#
# bash 3.2 SAFE: no `case` inside command substitution (memory
# bash32-case-in-substitution-zsh-repro-trap — a silent no-op that `bash -n`, shellcheck and zsh all
# pass). Absolute-prefix tests use `${x#/}` instead. Ships to launchd ⇒ tested under /bin/bash.
set -uo pipefail

TOOL=bats-shim-parity-lint

# ── resolve $0 THROUGH symlinks before deriving the repo root ──────────────────────────────────
# Everything under ~/.claude/scripts/ is a per-file symlink into this checkout, so a bare
# `dirname "$0"` yields ~/.claude — which has no bin/cc-bats — and the DEPLOYED copy would then
# judge against a nonexistent expectation and report NO-DATA forever. Same lesson as
# test-hermeticity-lint.sh:26. No `readlink -f`: that is GNU-only and this box ships BSD userland.
SELF="$0"
_hops=0
while [ -L "$SELF" ]; do
  _hops=$((_hops + 1))
  if [ "$_hops" -gt 32 ]; then
    printf '%s: NO-DATA — symlink loop resolving %s\n' "$TOOL" "$0" >&2
    exit 3
  fi
  _link="$(readlink "$SELF")"
  if [ "${_link#/}" != "$_link" ]; then SELF="$_link"; else SELF="$(dirname "$SELF")/$_link"; fi
done
REPO_ROOT="$(cd "$(dirname "$SELF")/.." 2>/dev/null && pwd -P)" || REPO_ROOT=""

usage() {
  printf 'usage: %s [--json] [--quiet] [-h|--help]\n' "$TOOL"
  printf '  Verifies row 13 shadow mode: /opt/homebrew/bin/bats still resolves to bin/cc-bats.\n'
  printf '  Exit: 0 NOT-ACTIVE|OK|DISABLED · 1 DRIFT · 2 STALE-SEED · 3 NO-DATA · 64 usage\n'
  printf '  Env (set-but-EMPTY honoured verbatim):\n'
  # shellcheck disable=SC2016  # deliberate: this is HELP TEXT — the operator must see the literal
  # '$HOME/.claude/...' form, not this process's expansion of it.
  printf '    CC_BATS_SEED         seed path (default $HOME/.claude/state/cc-bats-real)\n'
  printf '    CC_BATS_SHIM_PATH    judged path (default /opt/homebrew/bin/bats)\n'
  printf '    CC_BATS_EXPECT       required target (default <repo>/bin/cc-bats)\n'
  printf '    CC_BATS_PARITY_LINT  =off disables the check (exit 0, verdict DISABLED)\n'
}

JSON=0
QUIET=0
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--json" ]; then
    JSON=1
  elif [ "$1" = "--quiet" ]; then
    QUIET=1
  elif [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    usage
    exit 0
  else
    printf '%s: unknown argument: %s\n' "$TOOL" "$1" >&2
    usage >&2
    exit 64
  fi
  shift
done

# ── seams: unset / set-empty / set are three distinct states ───────────────────────────────────
if [ -n "${CC_BATS_SEED+set}" ]; then
  SEED="$CC_BATS_SEED"
else
  # Byte-for-byte the shim's own default (bin/cc-bats:65). A lint that judges a DIFFERENT file than
  # the subject reads is worse than no lint: it reports OK about a path nothing consults.
  SEED="$HOME/.claude/state/cc-bats-real"
fi
if [ -n "${CC_BATS_SHIM_PATH+set}" ]; then SHIM_PATH="$CC_BATS_SHIM_PATH"; else SHIM_PATH="/opt/homebrew/bin/bats"; fi
if [ -n "${CC_BATS_EXPECT+set}" ]; then EXPECT="$CC_BATS_EXPECT"; else EXPECT="$REPO_ROOT/bin/cc-bats"; fi

# ── helpers ────────────────────────────────────────────────────────────────────────────────────

# jesc <string> — JSON-escape. Parameter expansion rather than `sed`: no EXTERNAL process per field,
# so on the loaded box this row exists to fix a JSON consumer cannot be handed a half-escaped object
# by an exec that failed. (The `$( )` call site still forks a subshell — this removes the exec, not
# the fork.) Also sidesteps SC2001 rather than leaning on the repo-wide waiver.
jesc() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

# resolve_phys <path> — the fully symlink-resolved, physicalised path; empty + rc1 if unresolvable.
# Called from `$( )`, hence `${link#/}` rather than `case` (bash 3.2 trap, see header).
resolve_phys() {
  local p="$1" hops=0 link d b
  [ -n "$p" ] || return 1
  while [ -L "$p" ]; do
    hops=$((hops + 1))
    [ "$hops" -le 32 ] || return 1
    link="$(readlink "$p")" || return 1
    [ -n "$link" ] || return 1
    if [ "${link#/}" != "$link" ]; then p="$link"; else p="$(dirname "$p")/$link"; fi
  done
  [ -e "$p" ] || return 1
  d="$(dirname "$p")"
  b="$(basename "$p")"
  d="$(cd "$d" 2>/dev/null && pwd -P)" || return 1
  printf '%s/%s' "$d" "$b"
}

VERDICT=""
RC=0
REASON=""
SEED_PRESENT=false
SHIM_PHYS=""
EXPECT_PHYS=""
TARGET=""
TARGET_STATE="unread"

# judge — sets the globals above. Ordering is deliberate and load-bearing:
#   the ACTIVATION question (is there a seed at all?) is answered FIRST, because on a machine
#   without shadow mode every later check would fire against a perfectly healthy Homebrew symlink.
judge() {
  if [ "${CC_BATS_PARITY_LINT:-on}" = "off" ]; then
    VERDICT=DISABLED; RC=0
    REASON="kill switch CC_BATS_PARITY_LINT=off — no check performed"
    return 0
  fi

  # 1 — activation marker.
  if [ -n "$SEED" ] && [ -f "$SEED" ]; then
    SEED_PRESENT=true
  elif [ -n "$SEED" ] && [ -e "$SEED" ]; then
    # A directory (or socket, or fifo) where the seed should be is a broken install, not an answer.
    VERDICT=NO-DATA; RC=3
    REASON="seed path exists but is not a regular file: $SEED"
    return 0
  else
    VERDICT=NOT-ACTIVE; RC=0
    REASON="no seed at ${SEED:-<empty>} — shadow mode was never activated"
    return 0
  fi

  # 2 — both sides of the comparison must be readable before any drift claim.
  if [ -z "$EXPECT" ] || [ ! -e "$EXPECT" ]; then
    VERDICT=NO-DATA; RC=3
    REASON="expected shim target is unreadable: ${EXPECT:-<empty>}"
    return 0
  fi
  if [ -z "$SHIM_PATH" ]; then
    VERDICT=NO-DATA; RC=3
    REASON="judged path is empty (CC_BATS_SHIM_PATH set to empty)"
    return 0
  fi
  if [ ! -e "$SHIM_PATH" ]; then
    if [ -L "$SHIM_PATH" ]; then
      REASON="judged path is a DANGLING symlink — unresolvable: $SHIM_PATH -> $(readlink "$SHIM_PATH")"
    else
      REASON="judged path is absent entirely: $SHIM_PATH"
    fi
    VERDICT=NO-DATA; RC=3
    return 0
  fi

  SHIM_PHYS="$(resolve_phys "$SHIM_PATH")" || SHIM_PHYS=""
  EXPECT_PHYS="$(resolve_phys "$EXPECT")" || EXPECT_PHYS=""
  if [ -z "$SHIM_PHYS" ] || [ -z "$EXPECT_PHYS" ]; then
    VERDICT=NO-DATA; RC=3
    REASON="could not physicalise one side (shim='${SHIM_PHYS}' expect='${EXPECT_PHYS}')"
    return 0
  fi

  # 3 — THE drift check. Deliberately BEFORE the seed-content read: a restored Homebrew symlink is
  #     actionable regardless of what the seed happens to say, and it is the costlier failure.
  if [ "$SHIM_PHYS" != "$EXPECT_PHYS" ]; then
    VERDICT=DRIFT; RC=1
    REASON="$SHIM_PATH no longer resolves to cc-bats"
    return 0
  fi

  # 4 — the recording itself.
  TARGET="$(head -1 "$SEED" 2>/dev/null | tr -d '[:space:]')"
  if [ -z "$TARGET" ]; then
    VERDICT=NO-DATA; RC=3
    TARGET_STATE=empty
    REASON="seed file is empty or unreadable: $SEED"
    return 0
  fi
  if [ ! -e "$TARGET" ]; then
    TARGET_STATE=missing
  elif [ -d "$TARGET" ]; then
    TARGET_STATE=directory
  elif [ ! -x "$TARGET" ]; then
    TARGET_STATE=not-executable
  else
    TARGET_STATE=ok
  fi
  if [ "$TARGET_STATE" != "ok" ]; then
    VERDICT=STALE-SEED; RC=2
    REASON="seeded real bats is $TARGET_STATE: $TARGET"
    return 0
  fi

  VERDICT=OK; RC=0
  REASON="shadow mode intact: $SHIM_PATH -> cc-bats, real bats at $TARGET"
  return 0
}

judge

# ── report ─────────────────────────────────────────────────────────────────────────────────────
if [ "$JSON" -eq 1 ]; then
  printf '{"tool":"%s","verdict":"%s","rc":%s,"reason":"%s",' \
    "$(jesc "$TOOL")" "$(jesc "$VERDICT")" "$RC" "$(jesc "$REASON")"
  printf '"seed":"%s","seed_present":%s,' "$(jesc "$SEED")" "$SEED_PRESENT"
  printf '"shim_path":"%s","shim_phys":"%s",' "$(jesc "$SHIM_PATH")" "$(jesc "$SHIM_PHYS")"
  printf '"expect":"%s","expect_phys":"%s",' "$(jesc "$EXPECT")" "$(jesc "$EXPECT_PHYS")"
  printf '"target":"%s","target_state":"%s"}\n' "$(jesc "$TARGET")" "$(jesc "$TARGET_STATE")"
elif [ "$QUIET" -eq 0 ]; then
  if [ "$VERDICT" = "OK" ]; then
    printf '%s: OK — %s\n' "$TOOL" "$REASON"
  elif [ "$VERDICT" = "NOT-ACTIVE" ]; then
    printf '%s: NOT-ACTIVE — %s.\n' "$TOOL" "$REASON"
    printf '  This is the HEALTHY default, not a warning: %s is Homebrew'"'"'s own and should be.\n' "$SHIM_PATH"
    printf '  Activate shadow mode only if you want the ~30%% absolute-path invocations covered too.\n'
  elif [ "$VERDICT" = "DISABLED" ]; then
    printf '%s: DISABLED — %s.\n' "$TOOL" "$REASON"
  elif [ "$VERDICT" = "DRIFT" ]; then
    printf '%s: ⛔ DRIFT — %s.\n' "$TOOL" "$REASON"
    printf '    expected (physical): %s\n' "$EXPECT_PHYS"
    printf '    actual   (physical): %s\n' "$SHIM_PHYS"
    printf '  A "brew upgrade bats-core" restores the Homebrew-owned symlink SILENTLY. Nothing breaks —\n'
    printf '  the ~30%% of bats invocations that use the ABSOLUTE path are simply back at full\n'
    printf '  interactive priority, competing with every live session. Measured 2026-07-29.\n'
    printf '  Operator fix (mutates a package-manager-owned path — your call):\n'
    printf '      ln -sfn %s %s\n' "$EXPECT" "$SHIM_PATH"
    printf '  Or accept it and stand shadow mode down:  rm -f %s\n' "$SEED"
  elif [ "$VERDICT" = "STALE-SEED" ]; then
    printf '%s: ⛔ STALE-SEED — %s.\n' "$TOOL" "$REASON"
    printf '    seed: %s\n' "$SEED"
    printf '  The shim is still installed, so this is not an outage: cc-bats falls back to its\n'
    printf '  Cellar sweep (bin/cc-bats:106-118), which GUESSES a version by sort order. Re-record\n'
    printf '  the real binary so it never has to guess:\n'
    printf '      find /opt/homebrew/Cellar/bats-core /opt/homebrew/opt/bats-core -maxdepth 3 \\\n'
    printf '           -name bats -type f -perm -u+x 2>/dev/null | sort -V | tail -1\n'
    printf '      printf '"'"'%%s\\n'"'"' <that path> > %s\n' "$SEED"
  else
    printf '%s: ⛔ NO-DATA — %s.\n' "$TOOL" "$REASON"
    printf '  NO VERDICT. This is not a pass: nothing was verified about shadow mode.\n'
  fi
fi

exit "$RC"
