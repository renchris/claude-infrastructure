#!/usr/bin/env bats
# handoff-fire.sh self-close — SELF-IDENTITY: is the pane we are about to retire actually OURS?
# (2026-08-08, item 71909cbeee08, which CORRECTS 4cd42ec4's husk-pane diagnosis.)
#
# THE DEFECT, MEASURED. 2026-07-30, session c5f80b8b: `self-close --terminal` targeted pane
# 1C80FDB5-1BB5-4C5D-9107-899232DA2371, which was not among the 21 live iTerm2 panes; that session's
# real pane was 86A04828-EA39-4974-A022-8DD0385654BC (confirmed by reading its statusline). The
# close could never succeed, and the path then reported "claude exited, pane still open / the
# session is already gone" — both false. 4cd42ec4 had read that failure as an iTerm2 API blip and
# added a 4-attempt retry plus a husk page; retrying a write to a pane you do not own does not
# converge, so the item's own symptom outlived its fix.
#
# WHAT IS ALREADY CLOSED, AND WHY THIS IS NOT A RE-FIX OF IT. pane_proof (2026-08-05) refuses when
# the id names NO live pane, so the exact c5f80b8b trace is unreachable now. What it cannot see is
# the LATENT half the item named: an id that names a DIFFERENT LIVE pane passes it, and then /exit
# is typed into a stranger's composer and their pane is closed. On kitty that is the DEFAULT case,
# not the unlucky one — window ids are small integers kitty REUSES across restarts (22 live windows
# numbered 700-866 on this box, 2026-08-08). The fired-peer stamp gate is not a backstop either: it
# looks the stamp up UNDER THE SAME WRONG ID and can only ever agree with it.
#
# WHAT IS PINNED HERE:
#   1. The three verdicts, and that `not-mine` is reachable — a gate that cannot convict is inert.
#   2. THE POLARITY. `unknown` must NOT refuse. A false negative here aborts a HEALTHY self-close
#      and leaks its pane and worktree, a bill this file has paid twice (handoff-fire.sh :1461,
#      :3382). Every "the oracle could not answer" case below must proceed exactly as before.
#   3. THE FALSE-NEGATIVE GUARD. The pane's tty is matched against the WHOLE ancestry, not just
#      this process — the Bash tool's own shell has no controlling tty (`??`), and under the resume
#      path's `expect` wrapper CC sits on a nested pty while the pane's tty belongs to an ancestor.
#      Matching only our own tty calls both of those not-mine.
#   4. REPAIR vs REFUSE. A DEFAULTED id that is not ours is corrected to the pane the process tree
#      actually resolves (the DoD's prescribed pid→tty→pane reverse map). An id given EXPLICITLY by
#      --session-id is the caller's assertion and is REFUSED, never silently retargeted.
#
# The real script runs only as `self-close … --dry-run`, which prints and exits before any side
# effect: nothing is detached, no /exit is typed, no pane is closed. $HOME, the fired-dir and the
# terminal oracles are all fixtured, so the operator's real panes are never reachable.
#
# Every assertion is `[ ]`, `run`+status, or `… || false`. `[[ ]]` and `(( ))` are errexit-EXEMPT in
# bats and are silently DEAD anywhere but a body's last line — that has burned this repo twice.

setup() {
  # HERMETICITY (the repo's test-hermeticity ratchet). Fixturing $HOME is NOT sufficient for a suite
  # that names handoff-fire: the capacity gate refuses a net-new fire above 2.0/core and this box
  # lives above that, so an unpinned suite goes red-by-LOAD rather than by its subject; and three of
  # its seams default to an ABSOLUTE /tmp path or to a BARE NAME the subject then EXECUTES off the
  # operator's PATH, neither of which $HOME can redirect. An absent path is the right fixture —
  # these sensors fail open on one.
  export CC_FIRE_CAPACITY_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-lock-"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"

  # PIN THE TERMINAL, both seams. These cases drive the iTerm2 oracle; run from inside kitty the
  # subject would take the kitty branch and the osascript stub below would never be consulted —
  # the suite's verdict silently becoming a function of which terminal the developer sits in, the
  # dependency that has broken suites in this repo twice (tests/handoff-selfclose.bats:26).
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1 CC_TERM=iterm2

  export HOME="$BATS_TEST_TMPDIR/home"          # hermeticity ratchet rule 1: never the live ~/
  mkdir -p "$HOME/.claude/bin" "$HOME/.claude/cc-registry" "$HOME/.claude/cc-roles"
  FIRED="$HOME/.claude/cc-fired"; mkdir -p "$FIRED"
  export CC_FIRED_DIR="$FIRED"

  # The it2 shim must EXIST or handoff-fire's `sed … | head -1` REAL_IT2 probe aborts the script
  # under pipefail before any gate runs (same fixture as tests/handoff-selfclose-session-pin.bats).
  printf '#!/bin/bash\nREAL_IT2="%s"\nexit 0\n' "$HOME/.claude/bin/it2" > "$HOME/.claude/bin/it2"
  chmod +x "$HOME/.claude/bin/it2"
  printf '#!/bin/bash\nexit 1\n' > "$HOME/.claude/bin/cc-in-kitty"   # ancestry: not kitty
  chmod +x "$HOME/.claude/bin/cc-in-kitty"

  SHIM="$BATS_TEST_TMPDIR/shim"; mkdir -p "$SHIM"

  # ── THE ANCESTRY SEAM ──────────────────────────────────────────────────────────────────────────
  # own_ancestry_pids walks from $$, whose value a test cannot know, so the shim maps ANY unmodelled
  # pid to the head of a synthetic chain: <caller> → 9001 → 9002 → 9003 → (end). $ANC_TTY_ON names
  # which link owns the pane's tty; every other link answers `??`, exactly as a process with no
  # controlling terminal does. Default 9003 — the DEEPEST link — so the ordinary case is the one
  # that would break a "compare my own tty" implementation.
  # ONLY the two `-o ppid= -p` / `-o tty= -p` forms are intercepted; everything else delegates to
  # the real ps, because the gates downstream of the subject use ps for their own purposes and a
  # shim that answered those would be testing the fixture rather than the script.
  cat > "$SHIM/ps" <<'SH'
#!/usr/bin/env bash
fmt="" pid="" seen_p=0
args=("$@")
while [ $# -gt 0 ]; do
  case "$1" in
    -o) fmt="$fmt${2:-}"; shift 2 ;;
    -p) pid="${2:-}"; seen_p=1; shift 2 ;;
    *)  shift ;;
  esac
done
if [ "$seen_p" = 1 ] && [ "$fmt" = "ppid=" ]; then
  case "$pid" in
    9001) printf '9002\n' ;;
    9002) printf '9003\n' ;;
    9003) : ;;                      # end of chain
    *)    printf '9001\n' ;;        # the caller, whatever pid bats gave it
  esac
  exit 0
fi
if [ "$seen_p" = 1 ] && [ "$fmt" = "tty=" ]; then
  IFS=, read -r -a ps_list <<< "$pid"
  for p in "${ps_list[@]}"; do
    if [ "$p" = "${ANC_TTY_ON:-9003}" ]; then printf '%s\n' "${ANC_TTY:-ttysMINE}"; else printf '??\n'; fi
  done
  exit 0
fi
exec /bin/ps "${args[@]}"
SH

  # ── THE iTerm2 ORACLE ──────────────────────────────────────────────────────────────────────────
  # ONE stub serves both callers, told apart exactly as the script tells them apart: _as_tty_query
  # passes the pane id as argv, _it2_pane_tty_listing passes none.
  #   $OSA_DEAD=1     → the AppleScript bridge answers nothing at all (the `unknown` control)
  #   $PANE_TTYS      → "<pane-id> <tty>" pairs, one per line; the pane map both calls read
  cat > "$SHIM/osascript" <<'SH'
#!/usr/bin/env bash
[ -n "${OSA_DEAD:-}" ] && exit 0
uuid=""
while [ $# -gt 0 ]; do
  case "$1" in
    -e) shift 2 2>/dev/null || shift ;;    # -e '<script>' (delay / as_write) → no-op success
    -)  shift ;;
    *)  uuid="$1"; shift ;;
  esac
done
map="${PANE_TTYS:-}"
if [ -n "$uuid" ]; then                    # _as_tty_query: one pane → its tty
  printf '%s\n' "$map" | while read -r id t; do
    [ "$id" = "$uuid" ] && { printf '%s' "$t"; break; }
  done
  exit 0
fi
printf '%s\n' "$map" | while read -r id t; do    # _it2_pane_tty_listing: id<TAB>tty per session
  [ -n "$id" ] || continue
  printf '%s\t%s\n' "$id" "$t"
done
exit 0
SH

  # only `git rev-parse --is-inside-work-tree` is hit before the dry-run branch — report "not a work
  # tree" so the dirty-tree guard is skipped, hermetically and independently of the test's CWD.
  printf '#!/usr/bin/env bash\n[ "${1:-}" = rev-parse ] && exit 1\nexit 0\n' > "$SHIM/git"
  chmod +x "$SHIM/ps" "$SHIM/osascript" "$SHIM/git"
  export PATH="$SHIM:$PATH"

  # The default world: two live panes. PANE-MINE sits on this ancestry's tty; PANE-OTHER does not.
  export PANE_TTYS="PANE-MINE /dev/ttysMINE
PANE-OTHER /dev/ttysOTHER"

  WORK="$BATS_TEST_TMPDIR/work"; mkdir -p "$WORK"
  # $WORK must NOT sit inside a git repo: the dirty-tree gate runs BEFORE the dry-run branch, so a
  # git-visible $WORK would preempt the subject and every integration case would assert on the wrong
  # refusal. Asserted, never assumed — a fixture that quietly stops isolating is a vacuous pass.
  if ( cd "$WORK" && git rev-parse --is-inside-work-tree >/dev/null 2>&1 ); then
    echo "FIXTURE BROKEN: \$WORK is inside a git repo — the dirty-tree gate would preempt the subject" >&2
    return 1
  fi

  PF="$BATS_TEST_TMPDIR/prompt.txt"; printf 'probe\n' > "$PF"   # --recycle refuses without one

  # The units under test, extracted individually — the established pattern here
  # (tests/handoff-fire-kitty.bats:124). hf_bounded is a passthrough for the same reason that file
  # gives: these are extracted, not sourced, so the real bound helper is not in scope.
  hf_bounded() { "$@"; }
  eval "$(sed -n '/^kitty_identity() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^in_kitty() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^_as_tty_query() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^as_tty() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^_it2_pane_tty_listing() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^own_ancestry_pids() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^own_ancestry_ttys() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^pane_ownership() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^own_pane_id() {/,/^}/p' "$HF")"
}

# Drive the real script's self-close arm in $WORK. The environment's CLAIM about which pane this is
# comes from $1; the process tree's EVIDENCE comes from the ps shim.
sc() { # $1=ITERM_SESSION_ID value  $2…=extra args
  local it="$1"; shift
  run env ITERM_SESSION_ID="$it" \
      /bin/bash -c 'cd "$1" || exit 99; shift; exec /bin/bash "$@"' \
      _ "$WORK" "$HF" self-close --terminal --dry-run "$@"
}

stamp() { # $1=pane id → a fired-peer stamp so the origin gate lets the close through
  command -v jq >/dev/null 2>&1 || return 1   # a skip here would be a NON-VERDICT, not a pass
  jq -n --arg p "$1" --arg c "$(cd "$WORK" && pwd -P)" \
     '{paneUUID:$p, cwd:$c, firedBy:"identity-suite", firedAt:"2026-08-08T00:00:00Z",
       selfRetire:true, schema:2, originClass:"fired-peer", closedAt:null, succession:null}' \
     > "$FIRED/$1.json"
  [ -s "$FIRED/$1.json" ]
}

# ── 1. THE ORACLE — three verdicts, and each one reachable ───────────────────────────────────────

@test "pane_ownership: the pane on this ancestry's tty is MINE" {
  [ "$(pane_ownership PANE-MINE)" = mine ]
}

@test "pane_ownership: a DIFFERENT live pane is NOT-MINE — the latent danger, now convictable" {
  # THE WHOLE POINT. This pane is live and enumerable, so pane_proof passes it; only the process
  # tree can say it is not ours. Without this verdict the gate is inert and the item is unfixed.
  [ "$(pane_ownership PANE-OTHER)" = not-mine ]
}

@test "pane_ownership: the tty may be owned by ANY ancestor, not by us (the expect/nested-pty case)" {
  # The Bash tool's own shell has no controlling tty, and under `expect` CC sits on a nested pty
  # while the pane's tty belongs to an ancestor. An implementation comparing only its OWN tty calls
  # both of those not-mine and aborts healthy closes. Pin both ends of the chain.
  export ANC_TTY_ON=9003; [ "$(pane_ownership PANE-MINE)" = mine ]   # deepest link owns it
  export ANC_TTY_ON=9001; [ "$(pane_ownership PANE-MINE)" = mine ]   # nearest link owns it
}

@test "pane_ownership: an unreadable AppleScript bridge is UNKNOWN, never not-mine" {
  # THE POLARITY, at the oracle. A wedged terminal API is not evidence about the pane; answering
  # not-mine here would refuse every self-close on a box whose bridge hiccuped.
  export OSA_DEAD=1
  [ "$(pane_ownership PANE-MINE)" = unknown ]
}

@test "pane_ownership: a pane the terminal does not enumerate is UNKNOWN (pane_proof owns that)" {
  [ "$(pane_ownership PANE-GHOST)" = unknown ]
}

@test "pane_ownership: an empty id is UNKNOWN" {
  [ "$(pane_ownership '')" = unknown ]
}

@test "pane_ownership: UNKNOWN when the ancestry has no tty at all (a launchd/daemon caller)" {
  # Every link answers `??`. Nothing to compare against ⇒ abstain, do not convict.
  export ANC_TTY_ON=none
  [ "$(pane_ownership PANE-MINE)" = unknown ]
}

@test "own_pane_id: reverse-maps the ancestry's tty back to the pane that owns it" {
  [ "$(own_pane_id)" = PANE-MINE ]
}

@test "own_pane_id: empty when no enumerated pane matches this ancestry (never a guess)" {
  export PANE_TTYS="PANE-OTHER /dev/ttysOTHER"
  [ -z "$(own_pane_id)" ]
}

# ── 2. THE GATE — repair a defaulted id, refuse an asserted one, never touch `unknown` ───────────

@test "gate: a DEFAULTED id that is not ours is CORRECTED to the pane we actually live in" {
  # The DoD's prescribed repair (reverse-map pid→tty→pane). Pre-fix this retired PANE-OTHER — a
  # live pane belonging to someone else. The stamp is on PANE-MINE, so reaching the dry-run at all
  # proves the corrected id is USABLE by every gate downstream, not merely printed.
  stamp PANE-MINE || false
  sc "w0t0p0:PANE-OTHER"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'self-identity CORRECTED' || false
  printf '%s\n' "$output" | grep -qE '^pane: +PANE-MINE$' || false
}

@test "gate: an EXPLICIT --session-id that is not ours is REFUSED, never silently retargeted" {
  # --session-id is the caller's assertion. Repairing it would be the same surprise in the other
  # direction: the caller named a pane and a different one closed.
  stamp PANE-MINE || false
  sc "w0t0p0:PANE-MINE" --session-id PANE-OTHER
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF 'is NOT this session'"'"'s pane' || false
  printf '%s\n' "$output" | grep -qF 'ASSERTION BY THE CALLER' || false
  ! printf '%s\n' "$output" | grep -qF 'CORRECTED' || false
}

@test "gate: not-ours AND unrepairable → REFUSES; nothing typed, nothing closed" {
  # No enumerated pane sits on this ancestry, so there is no safe pane to retire in its place.
  export PANE_TTYS="PANE-OTHER /dev/ttysOTHER"
  sc "w0t0p0:PANE-OTHER"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF 'this session stays alive' || false
}

@test "POLARITY: an unreadable bridge does NOT refuse — it proceeds on the env, as before" {
  # THE CONTROL THAT MATTERS MOST. If this ever goes red the gate has started refusing on absence
  # of evidence, which leaks the pane and worktree of every peer that finishes on a hiccuping box.
  # It must land on the ORIGIN gate — the pre-gate behaviour — naming the id the ENV gave.
  export OSA_DEAD=1
  sc "w0t0p0:PANE-WHATEVER"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF 'self-identity UNPROVEN' || false
  printf '%s\n' "$output" | grep -qF 'pane PANE-WHATEVER has no fired-peer stamp' || false
}

@test "POSITIVE CONTROL: when the env is RIGHT the gate is silent and changes nothing" {
  # Without this, every assertion above is equally satisfied by a gate that fires on everything.
  stamp PANE-MINE || false
  sc "w0t0p0:PANE-MINE"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qE '^pane: +PANE-MINE$' || false
  ! printf '%s\n' "$output" | grep -qF 'CORRECTED' || false
  ! printf '%s\n' "$output" | grep -qF 'UNPROVEN' || false
  ! printf '%s\n' "$output" | grep -qF 'REFUSED' || false
}

# ── 3. --recycle SHARES THE DEFAULT, SO IT SHARES THE GATE ──────────────────────────────────────
# And it needs it MORE. Recycle does not merely close the pane it names — it types /exit AND a
# launcher command into it, so a stale id kills a stranger's turn and relaunches a CC in their pane
# against THIS session's worktree and brief. One gate serves both call sites (verify_self_pane), so
# these also pin that the two cannot drift apart into different state models.

rc() { # $1=ITERM_SESSION_ID value  $2…=extra args
  local it="$1"; shift
  run env ITERM_SESSION_ID="$it" \
      /bin/bash -c 'cd "$1" || exit 99; shift; exec /bin/bash "$@"' \
      _ "$WORK" "$HF" --recycle --prompt-file "$PF" --dry-run "$@"
}

@test "recycle: a DEFAULTED id that is not ours is CORRECTED, not typed into" {
  rc "w0t0p0:PANE-OTHER"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'self-identity CORRECTED (--recycle)' || false
  printf '%s\n' "$output" | grep -qF 'PANE-MINE' || false
}

@test "recycle: not-ours and unrepairable → REFUSED, and it names the worse consequence" {
  export PANE_TTYS="PANE-OTHER /dev/ttysOTHER"
  rc "w0t0p0:PANE-OTHER"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF -e '--recycle REFUSED' || false   # -e: the pattern starts with --
  printf '%s\n' "$output" | grep -qF 'launcher command into a DIFFERENT live session' || false
}

@test "recycle POLARITY: an unreadable bridge does NOT refuse" {
  export OSA_DEAD=1
  rc "w0t0p0:PANE-WHATEVER"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'self-identity UNPROVEN' || false
}

@test "recycle POSITIVE CONTROL: a correct env is silent and unchanged" {
  rc "w0t0p0:PANE-MINE"
  [ "$status" -eq 0 ]
  ! printf '%s\n' "$output" | grep -qF 'CORRECTED' || false
  ! printf '%s\n' "$output" | grep -qF 'REFUSED' || false
}

@test "the gate runs BEFORE every consumer of the pane id" {
  # Ordering is load-bearing and invisible at runtime: the stamp lookup, the assignee tty read, the
  # successor-equality check and the watcher all key on $SC_SID. An identity settled after those
  # have reasoned about it is a footnote, not a gate. Proven behaviourally — the stamp is on
  # PANE-MINE only, so a gate running after the stamp lookup would refuse with PANE-OTHER's miss.
  stamp PANE-MINE || false
  sc "w0t0p0:PANE-OTHER"
  [ "$status" -eq 0 ]
  ! printf '%s\n' "$output" | grep -qF 'no fired-peer stamp' || false
}
