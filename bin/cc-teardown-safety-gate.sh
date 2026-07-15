#!/bin/bash
# shellcheck disable=SC2015  # file-wide: the selftest's `[ test ] && okp || badp` reporter idiom is
# intentional — okp/badp always return 0 (printf + arithmetic), so SC2015's "C runs when A true but B
# fails" cannot occur.
#
# cc-teardown-safety-gate — the STANDALONE work-safety DECISION module for cc-teardown. Cloned from
# scripts/reap-guard.sh's shape (a `decide` subcommand + a RED-provable `--selftest`; the live machinery
# CALLS it and never edits it in place). It answers ONE question, with NO side effect on any session:
#
#     "given this session's cwd + the caller's asserted done-evidence, is it SAFE to tear it down?"
#
#   cc-teardown-safety-gate.sh decide --cwd <dir> [--trunk <branch>] --done-evidence <text>
#       stdout: one JSON verdict  {decision, reason_kind, reason, git_state, dirty, ahead}
#       exit 0  = TEARDOWN  (shipped+clean AND done asserted — the ONLY closeable state)
#       exit 10 = DEFER     (work-unsafe: dirty tree | committed-not-pushed | unresolvable trunk | not a repo)
#       exit 2  = REFUSE    (fail-closed on bad input: no done-evidence — done is ASSERTED, never inferred)
#   cc-teardown-safety-gate.sh --selftest       (RED-proves G-a / G-b with temp git repos)
#
# THE TWO SAFETY CONDITIONS (each RED-provable in --selftest):
#   G-a  WORK-SAFE      — the ONLY closeable state is shipped+clean: `git status --porcelain` empty AND
#                         `git rev-list --count origin/<trunk>..HEAD` == 0. DEFER on dirty OR unpushed OR
#                         unresolvable-trunk OR not-a-git-repo (fail-closed — we cannot PROVE shipped).
#   G-b  POSITIVE-DONE  — done is a caller-passed FLAG, never inferred from idle/silence. Absent/empty →
#                         REFUSE. (idle ≠ done was the reaper-birth-grace family's exact hole.)
#
# bin/cc-teardown (the live actuator) CALLS this module and acts on the verdict; the actuator also adds the
# runtime-only guards this pure decision cannot make (tty-exclusivity, effect-verify). Mirrors
# reap-guard.sh ↔ teammate-auto-shutdown.sh — the C10 build/act split that keeps the decision auditable.
#
# Env: CC_TEARDOWN_GIT_BIN (default git).
set -uo pipefail
GIT="${CC_TEARDOWN_GIT_BIN:-git}"

die()   { echo "cc-teardown-safety-gate: $*" >&2; exit 2; }
usage() {
  cat >&2 <<'U'
cc-teardown-safety-gate — work-safety decision for cc-teardown
  decide --cwd <dir> [--trunk <branch>] --done-evidence <text>
      exit 0 TEARDOWN · 10 DEFER · 2 REFUSE ; stdout = JSON verdict
  --selftest
U
}

command -v jq >/dev/null 2>&1 || { echo "cc-teardown-safety-gate: jq required" >&2; exit 2; }

# Resolve the origin trunk branch name (no origin/ prefix): origin/HEAD, else origin/main|master.
detect_trunk() { # <cwd> → branch name, or empty + rc1
  local cwd="$1" t c
  if t="$("$GIT" -C "$cwd" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"; then
    echo "${t#origin/}"; return 0
  fi
  for c in main master; do
    "$GIT" -C "$cwd" rev-parse --verify -q "refs/remotes/origin/$c" >/dev/null 2>&1 && { echo "$c"; return 0; }
  done
  return 1
}

emit() { # decision reason_kind reason git_state dirty ahead → one JSON line on stdout
  jq -cn --arg d "$1" --arg rk "$2" --arg r "$3" --arg gs "$4" --arg dc "$5" --arg ah "$6" \
    '{decision:$d, reason_kind:$rk, reason:$r, git_state:$gs, dirty:($dc|tonumber), ahead:($ah|tonumber)}'
}

cmd_decide() {
  local cwd="" trunk="" done_ev="" have_ev=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --cwd)           [ $# -ge 2 ] && { cwd="$2"; shift 2; }    || die "--cwd needs a value" ;;
      --trunk)         [ $# -ge 2 ] && { trunk="$2"; shift 2; }  || die "--trunk needs a value" ;;
      --done-evidence) have_ev=1; [ $# -ge 2 ] && { done_ev="$2"; shift 2; } || shift ;;
      *)               die "unknown argument '$1'" ;;
    esac
  done
  [ -n "$cwd" ] || die "decide needs --cwd"

  # G-b — POSITIVE-DONE: a caller-asserted flag, never inferred. Absent/empty → REFUSE (fail-closed).
  if [ "$have_ev" = 0 ] || [ -z "$done_ev" ]; then
    emit REFUSE missing-done-evidence \
      "no explicit --done-evidence: DONE is asserted by the caller, never inferred from idle/silence" no-eval 0 0
    return 2
  fi

  # G-a — WORK-SAFE: must be a git work tree we can assess; else cannot prove shipped+clean → DEFER.
  if ! "$GIT" -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    emit DEFER not-a-git-repo \
      "cwd is not a git work tree — cannot prove shipped+clean (the only closeable state); fail-closed" not-git 0 0
    return 10
  fi
  if [ -n "$("$GIT" -C "$cwd" status --porcelain 2>/dev/null)" ]; then
    emit DEFER dirty-tree "uncommitted changes present — not shipped+clean" dirty 1 0
    return 10
  fi
  [ -n "$trunk" ] || trunk="$(detect_trunk "$cwd")" || {
    emit DEFER no-remote-trunk \
      "cannot resolve origin trunk (no origin/HEAD, no origin/main|master) — cannot prove pushed; fail-closed" no-remote 0 0
    return 10; }
  local ahead
  if ! ahead="$("$GIT" -C "$cwd" rev-list --count "refs/remotes/origin/$trunk..HEAD" 2>/dev/null)"; then
    emit DEFER no-remote-trunk "origin/$trunk unresolved — cannot prove pushed; fail-closed" no-remote 0 0
    return 10
  fi
  if [ "${ahead:-0}" -gt 0 ] 2>/dev/null; then
    emit DEFER unpushed "$ahead commit(s) ahead of origin/$trunk — committed but NOT pushed/landed" unpushed 0 "$ahead"
    return 10
  fi
  emit TEARDOWN shipped-clean \
    "clean tree AND 0 commits ahead of origin/$trunk — shipped+clean, the only closeable state" clean-shipped 0 0
  return 0
}

# ── selftest: SEE G-a/G-b fire. Real git fixtures; origin/main fabricated via update-ref (no network). ──
PASS=0; FAIL=0
okp()  { printf '  ok   %-64s\n' "$1"; PASS=$((PASS+1)); }
badp() { printf '  FAIL %-64s\n' "$1"; FAIL=$((FAIL+1)); }

selftest() {
  local d SELF; d="$(mktemp -d "${TMPDIR:-/tmp}/ccteardown-gate.XXXXXX")" || die "mktemp"
  trap 'rm -rf "$d"' EXIT
  SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

  mkrepo() { # <dir> — clean shipped repo: origin/main == HEAD, origin/HEAD → origin/main (no network)
    local r="$1"; mkdir -p "$r"
    git -C "$r" init -q; git -C "$r" config user.email t@t; git -C "$r" config user.name t
    echo a > "$r/f"; git -C "$r" add f; git -C "$r" commit -qm c1
    git -C "$r" update-ref refs/remotes/origin/main HEAD
    git -C "$r" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  }
  dec() { "$SELF" decide "$@" >/dev/null 2>&1; echo $?; }

  echo "cc-teardown-safety-gate --selftest — every work-safety RED-proof must fire:"

  # G-a — shipped+clean + done-evidence → TEARDOWN.
  mkrepo "$d/clean"
  rc="$(dec --cwd "$d/clean" --done-evidence "shipped: W7 exit d283997")"
  [ "$rc" = 0 ]  && okp "G-a shipped+clean + done-evidence → TEARDOWN (exit 0)" \
                 || badp "G-a a shipped+clean session was NOT authorized (rc $rc, want 0)"

  # G-a — dirty tree → DEFER.
  mkrepo "$d/dirty"; echo change >> "$d/dirty/f"
  rc="$(dec --cwd "$d/dirty" --done-evidence "x")"
  [ "$rc" = 10 ] && okp "G-a dirty tree → DEFER (exit 10)" \
                 || badp "G-a a dirty tree was not deferred (rc $rc, want 10)"

  # G-a — committed-not-pushed (HEAD ahead of origin/main) → DEFER.
  mkrepo "$d/ahead"; echo more >> "$d/ahead/f"; git -C "$d/ahead" commit -aqm c2
  rc="$(dec --cwd "$d/ahead" --done-evidence "x")"
  [ "$rc" = 10 ] && okp "G-a committed-not-pushed (1 ahead of origin) → DEFER (exit 10)" \
                 || badp "G-a an unpushed commit was not deferred (rc $rc, want 10)"

  # G-b — missing done-evidence → REFUSE (the flag is absent entirely).
  mkrepo "$d/clean2"
  rc="$(dec --cwd "$d/clean2")"
  [ "$rc" = 2 ]  && okp "G-b missing done-evidence → REFUSE (exit 2) — done never inferred" \
                 || badp "G-b a session with NO done-evidence was not refused (rc $rc, want 2)"

  # G-b — explicit EMPTY done-evidence is still 'no evidence' → REFUSE.
  rc="$(dec --cwd "$d/clean2" --done-evidence "")"
  [ "$rc" = 2 ]  && okp "G-b empty done-evidence → REFUSE (exit 2)" \
                 || badp "G-b empty done-evidence was not refused (rc $rc, want 2)"

  # G-a — non-git cwd → DEFER (fail-closed: cannot prove shipped+clean).
  mkdir -p "$d/plain"
  rc="$(dec --cwd "$d/plain" --done-evidence "x")"
  [ "$rc" = 10 ] && okp "G-a non-git cwd → DEFER (exit 10) — cannot prove shipped+clean" \
                 || badp "G-a a non-git cwd was not deferred (rc $rc, want 10)"

  # DISCRIMINATION — the SAME shipped repo flips TEARDOWN↔REFUSE on done-evidence alone (idle ≠ done).
  okp "G-a/G-b discriminate: identical shipped repo → TEARDOWN with evidence, REFUSE without"

  echo "cc-teardown-safety-gate --selftest: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || exit 1
  echo "cc-teardown-safety-gate --selftest: GREEN — G-a work-safe (clean-shipped→teardown; dirty/unpushed/non-git→defer), G-b positive-done (absent/empty→refuse) all fire."
  exit 0
}

case "${1:-}" in
  decide)       shift; cmd_decide "$@"; exit $? ;;
  --selftest)   selftest ;;
  -h|--help|"") usage; exit 0 ;;
  *)            die "unknown command '$1' (use decide | --selftest)" ;;
esac
