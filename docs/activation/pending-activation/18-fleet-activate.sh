#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 17-fleet-activate  —  bring the launchd FLEET to its DECLARED state in ONE operator command
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: reads the declaration `launchd/fleet.manifest` (DAEMON_FLEET_V2 §4.1) and, for every label
#   declared `expect = run` that is not already loaded-and-enabled, runs the four-step reconcile:
#
#     launchctl bootout   gui/<uid>/<label>          # only if loaded — makes the reload idempotent
#     launchctl enable    gui/<uid>/<label>          # FIRST. see THE TRAP below. no-op when unset
#     launchctl bootstrap gui/<uid> <live-plist>     # the verdict
#     launchctl print     gui/<uid>/<label>          # self-verify — print, NEVER `list | grep`
#
#   then prints the whole fleet's state table and the exact next read. Labels declared `staged` or
#   `retired` are NEVER touched: those are undecided/deliberate, and activating them is exactly the
#   guess this design refuses to make (§6.4 — a genuinely ambiguous job is declared `staged`, i.e. a
#   decision SURFACED, never an alarm GUESSED).
#
# THE TRAP THIS SCRIPT EXISTS TO CLEAR: a label sitting in launchd's disabled database refuses
#   `bootstrap` with a bare `Bootstrap failed: 5: Input/output error` that names neither cause nor
#   cure (legacy `launchctl unload -w` writes that bit; `bootout` does NOT clear it). `enable` clears
#   it and is a no-op when the bit is unset — so it is unconditional and it goes FIRST. Measured
#   2026-07-29: 10 of 14 `com.claude.*` labels carry that bit in
#   /var/db/com.apple.xpc.launchd/disabled.501.plist, which is why the fleet has been dark since the
#   2026-07-27 19:02 reboot. `enable` is deliberately NOT in the `&&` chain: bootstrap is the verdict,
#   and a benign enable failure must not mask a load that would have worked.
#
# WHY C10 (agent stages; operator runs): loading a launchd job IS an activation and agents are
#   classifier-blocked from it. Everything above the CONFIRM gate is read-only.
#
# WHY A BARE RUN SHOUTS: the bare-run-then-`touch .done` idiom is what produced the 10-day silent
#   dispatcher outage — 02-load-dispatcher / 03-load-discovery were marked `.done` on Jul 19/20 and
#   NEITHER job was ever bootstrapped (activation-watch.sh axis 3). A marker records that the SCRIPT
#   RAN; only launchctl records that the EFFECT LANDED. So a bare run says, in words, that nothing
#   changed and that the marker must NOT be touched yet.
#
# WHAT IT ARMS: nothing new — `cc-blockers` calls `cc-fleet` synchronously, so the fleet rows are
#   live with ZERO activation (§4.6). This script closes them: it is the `recover_cmd` those rows
#   name. Until it is run, every declared-`run` label that is not S6 stays on the board.
#
# KILL SWITCHES (all env, never revert-as-plan):
#   CC_FLEET_RECONCILE=off             disables the reconciler (board + daemon); the verdict tail
#                                      below then reports that it is off rather than pretending green
#   launchctl bootout gui/$(id -u)/<label>     stop any single job
#   CC_FLEET_STALE_FACTOR=<n>          S5 staleness sensitivity (default 3)
# SEAMS: CC_REPO (checkout root) · CC_FLEET_MANIFEST (declaration path) · CC_FLEET_LAUNCHCTL_BIN
#
# RUN IT:  CONFIRM=1 bash ~/.claude/autonomy/pending-activation/17-fleet-activate.sh
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
set -uo pipefail

SELF_LIVE="$HOME/.claude/autonomy/pending-activation/17-fleet-activate.sh"
LAUNCHCTL="${CC_FLEET_LAUNCHCTL_BIN:-launchctl}"
LIVE_AGENTS="$HOME/Library/LaunchAgents"
UID_="$(id -u)"

deref() { # <path> → the real file behind any symlink chain (BSD-safe; readlink -f is GNU-only)
  local p="$1" t n=0
  while [ -L "$p" ] && [ "$n" -lt 20 ]; do
    t="$(readlink "$p")"
    case "$t" in /*) p="$t" ;; *) p="$(dirname "$p")/$t" ;; esac
    n=$(( n + 1 ))
  done
  printf '%s\n' "$p"
}
valid_root() { [ -n "${1:-}" ] && [ -e "$1/.git" ] && [ -d "$1/launchd" ]; }

# ── resolve the checkout, FAIL LOUD rather than guess ──────────────────────────────────────────────
# The `.git` gate is the anti-vacuous-pass guard (`-e`, not `-d`: a linked worktree's .git is a FILE).
# A sibling parity assert once resolved REPO=~/.claude through an underefed BASH_SOURCE and every leg
# exited 0 vacuously — backlog 816015ecb30b. ~/.claude has no .git, so it can never pose as the SSOT.
# The live copy of this script is a REAL FILE under ~/.claude/autonomy/pending-activation (not a
# symlink into the checkout), so the deref below resolves only for the REPO copy; the operator's run
# lands on the fallback. Both are validated the same way.
if [ -n "${CC_REPO:-}" ]; then
  valid_root "$CC_REPO" || {
    echo "✗ CC_REPO=$CC_REPO is not a checkout of this repo (needs .git and launchd/)." >&2
    echo "  Point it at a real checkout:  CC_REPO=\$HOME/Development/claude-infrastructure CONFIRM=1 bash $SELF_LIVE" >&2
    exit 2; }
  REPO="$CC_REPO"
else
  REPO=""
  _from_self="$(cd "$(dirname "$(deref "${BASH_SOURCE[0]}")")/../../.." 2>/dev/null && pwd)" || _from_self=""
  for _cand in "$_from_self" "$HOME/Development/claude-infrastructure"; do
    valid_root "$_cand" || continue
    [ -n "$REPO" ] || REPO="$_cand"                            # first valid root is the default…
    [ -f "$_cand/launchd/fleet.manifest" ] && { REPO="$_cand"; break; }   # …a checkout carrying the
  done                                                         # declaration wins outright
  [ -n "$REPO" ] || {
    echo "✗ could not resolve the checkout root from $(deref "${BASH_SOURCE[0]}") and no checkout at \$HOME/Development/claude-infrastructure." >&2
    echo "  Re-run naming it explicitly (the command that WORKS, not the one that should):" >&2
    echo "      CC_REPO=/path/to/claude-infrastructure CONFIRM=1 bash $SELF_LIVE" >&2
    exit 2; }
fi

MANIFEST="${CC_FLEET_MANIFEST:-$REPO/launchd/fleet.manifest}"
[ -f "$MANIFEST" ] || {
  echo "✗ fleet declaration absent: $MANIFEST" >&2
  echo "  Resolved checkout: $REPO — is it on a trunk that carries launchd/fleet.manifest (DAEMON_FLEET_V2 §4.1)?" >&2
  echo "      git -C $REPO log --oneline -1 ; git -C $REPO worktree list" >&2
  echo "      CC_REPO=<checkout-with-the-manifest> CONFIRM=1 bash $SELF_LIVE" >&2
  exit 2; }
command -v "$LAUNCHCTL" >/dev/null 2>&1 || { echo "✗ launchctl not found ($LAUNCHCTL) — is this macOS?" >&2; exit 2; }

echo "== 17-fleet-activate =="
echo "declaration: $MANIFEST"
echo "checkout:    $REPO"

# ── read the world ONCE (read-only launchctl only; nothing above the CONFIRM gate mutates) ─────────
DISABLED_DB="$("$LAUNCHCTL" print-disabled "gui/$UID_" 2>/dev/null || true)"
is_disabled() { printf '%s\n' "$DISABLED_DB" | grep -Fq "\"$1\" => disabled"; }
# `print`, never `list | grep`: print resolves the label in THIS domain and fails non-zero when it is
# absent, whereas a grep over `list` can match a substring of an unrelated label and reads a job that
# has already exited as present — it cannot tell loaded-and-healthy from loaded-and-failing.
# `</dev/null`: a launchctl invocation must never inherit — and therefore never EAT — the stdin some
# caller is reading a file from. The parse below is deliberately split into a pure-text pass and a
# launchctl pass for the same reason (a stdin-consuming child would silently truncate the manifest).
is_loaded()   { "$LAUNCHCTL" print "gui/$UID_/$1" >/dev/null 2>&1 </dev/null; }

trim() { local s="${1:-}"; s="${s#"${s%%[![:space:]]*}"}"; printf '%s' "${s%"${s##*[![:space:]]}"}"; }

# ── pass 1: parse the declaration (pure text — no subprocess touches this stdin) ───────────────────
LABELS=() EXPECTS=() ACTIVATES=()
while IFS='|' read -r f_label f_expect _f_interval _f_evidence _f_owner f_activate; do
  label="$(trim "${f_label:-}")"
  case "$label" in ''|'#'*) continue ;; esac
  LABELS+=("$label"); EXPECTS+=("$(trim "${f_expect:-}")"); ACTIVATES+=("$(trim "${f_activate:-}")")
done < "$MANIFEST"

[ "${#LABELS[@]}" -gt 0 ] || { echo "✗ $MANIFEST declares no labels — refusing to claim a reconciled fleet from an empty declaration" >&2; exit 2; }

# ── pass 2: declaration vs world → the work list ───────────────────────────────────────────────────
TODO=() TODO_WHY=() TODO_PLIST=()
for i in "${!LABELS[@]}"; do
  label="${LABELS[$i]}"
  [ "${EXPECTS[$i]}" = run ] || continue                     # staged / retired: declared undecided — never touched
  is_loaded "$label" && ! is_disabled "$label" && continue    # already at the declared state
  why="not loaded"
  is_loaded "$label" && why="loaded but DISABLED (bootout+enable+reload)"
  is_disabled "$label" && ! is_loaded "$label" && why="disabled AND not loaded"
  # plist source: the committed SSOT first. A LIVE-ONLY plist (in ~/Library/LaunchAgents, never
  # committed — currently com.claude.lead-supervisor) is still loadable, but it is one `rm` from
  # unrecoverable, so say so loudly instead of silently normalising it (§4.4 LIVE-ONLY).
  src="$REPO/launchd/$label.plist"
  if [ ! -f "$src" ]; then
    if [ -f "$LIVE_AGENTS/$label.plist" ]; then
      src="$LIVE_AGENTS/$label.plist"; why="$why · ⚠ LIVE-ONLY plist (not in git)"
    else
      src=""; why="$why · ✗ NO PLIST in $REPO/launchd or $LIVE_AGENTS"
    fi
  fi
  TODO+=("$label"); TODO_WHY+=("$why"); TODO_PLIST+=("$src")
done

declared_run=0
for i in "${!LABELS[@]}"; do [ "${EXPECTS[$i]}" = run ] && declared_run=$(( declared_run + 1 )); done
echo "declared: ${#LABELS[@]} label(s) · $declared_run expect=run · ${#TODO[@]} not at declared state"

if [ "${#TODO[@]}" -eq 0 ]; then
  echo "= every declared-run label is already loaded and enabled — nothing to do (idempotent no-op)."
else
  echo "Will reconcile (bootout-if-loaded → enable → bootstrap → verify with print):"
  for i in "${!TODO[@]}"; do
    note=""
    for j in "${!LABELS[@]}"; do
      [ "${LABELS[$j]}" = "${TODO[$i]}" ] || continue
      act="${ACTIVATES[$j]}"
      # A label with a BESPOKE activation script does more than bootstrap (symlinks, log dirs). The
      # generic reconcile still loads it — a job that loads and fails is reported FAILING (S4), which
      # is honest — but name the sibling script so the operator can close that gap if it does.
      case "$act" in ''|-|17-fleet-activate.sh) ;; *) note=" · bespoke activation exists: $act" ;; esac
    done
    printf '  %-38s %s%s\n' "${TODO[$i]}" "${TODO_WHY[$i]}" "$note"
  done
fi

if [ "${CONFIRM:-0}" != 1 ]; then
  cat <<EOF

── DRY RUN — NOTHING WAS CHANGED ─────────────────────────────────────────────────────────────────
No launchctl mutation ran. Not one label was enabled, bootstrapped or booted out. The fleet is in
exactly the state it was in before this run.

DO NOT touch the .done marker yet. A marker records that the SCRIPT RAN; only launchctl records that
the EFFECT LANDED. Marking this done after a bare run is precisely what kept the dispatcher dark for
10 days while the queue reported itself fully activated.

Apply it for real:
    CONFIRM=1 bash $SELF_LIVE
EOF
  exit 0
fi

echo
echo "== reconciling ${#TODO[@]} label(s) =="
rc=0
mkdir -p "$LIVE_AGENTS"
for i in "${!TODO[@]}"; do
  label="${TODO[$i]}"; src="${TODO_PLIST[$i]}"; live="$LIVE_AGENTS/$label.plist"
  echo "  ── $label"
  if [ -z "$src" ]; then
    echo "     ✗ no plist to load — SKIPPED (a label cannot be bootstrapped from a declaration alone)" >&2
    rc=1; continue
  fi
  if [ "$src" != "$live" ] && ! cp "$src" "$live"; then
    echo "     ✗ could not stage $src → $live" >&2; rc=1; continue
  fi
  if ! plutil -lint "$live" >/dev/null 2>&1; then
    echo "     ✗ $live fails plutil -lint — NOT loading a malformed plist" >&2; rc=1; continue
  fi
  # launchd refuses to start a job whose Standard*Path DIRECTORY is absent — the difference between
  # loaded-and-healthy and loaded-and-failing. `-o -` is mandatory: a bare `plutil -extract k json
  # <file>` REWRITES the plist in place (5 live LaunchAgents destroyed that way, 2026-07-25).
  for key in StandardOutPath StandardErrorPath; do
    p="$(plutil -extract "$key" raw -o - "$live" 2>/dev/null || true)"
    [ -n "$p" ] && mkdir -p "$(dirname "${p/#\~/$HOME}")"
  done
  if is_loaded "$label"; then
    "$LAUNCHCTL" bootout "gui/$UID_/$label" 2>/dev/null || echo "     (bootout rc=$? — continuing)"
  fi
  "$LAUNCHCTL" enable "gui/$UID_/$label" || echo "     (enable rc=$? — continuing; the bootstrap below is the verdict)"
  if "$LAUNCHCTL" bootstrap "gui/$UID_" "$live"; then
    if "$LAUNCHCTL" print "gui/$UID_/$label" >/dev/null 2>&1; then echo "     ✓ loaded and verified"
    else echo "     ✗ bootstrap returned 0 but the label does NOT resolve in gui/$UID_" >&2; rc=1; fi
  else
    echo "     ✗ bootstrap failed — if it printed EIO the disabled bit was re-written between the enable and here" >&2; rc=1
  fi
done

# ── final state table: re-read the world, never re-report the plan ────────────────────────────────
DISABLED_DB="$("$LAUNCHCTL" print-disabled "gui/$UID_" 2>/dev/null || true)"
echo
printf '== fleet state (re-read after reconcile) ==\n'
printf '  %-38s %-8s %-9s %-7s %s\n' LABEL EXPECT INSTALLED ENABLED LOADED
for i in "${!LABELS[@]}"; do
  label="${LABELS[$i]}"
  inst=no; [ -f "$LIVE_AGENTS/$label.plist" ] && inst=yes
  en=yes;  is_disabled "$label" && en=NO
  ld=NO;   is_loaded   "$label" && ld=yes
  printf '  %-38s %-8s %-9s %-7s %s\n' "$label" "${EXPECTS[$i]}" "$inst" "$en" "$ld"
done

echo
if [ "${CC_FLEET_RECONCILE:-on}" = off ]; then
  echo "== verdict: SKIPPED — CC_FLEET_RECONCILE=off (kill switch set; unset it for the real verdict) =="
else
  CCF=""
  for c in "$REPO/bin/cc-fleet" "$HOME/.claude/bin/cc-fleet"; do [ -x "$c" ] && { CCF="$c"; break; }; done
  if [ -n "$CCF" ]; then
    echo "== verdict: $CCF --check =="
    # capture THEN judge: `if cmd | sed` would test sed's status, so the verdict would depend on
    # pipefail being set rather than on the reconciler's own exit code.
    cout="$("$CCF" --check 2>&1 </dev/null)"; crc=$?
    [ -n "$cout" ] && printf '%s\n' "$cout" | sed 's/^/  /'
    if [ "$crc" -eq 0 ]; then echo "  ✓ every declared-run label is healthy (S6)"
    else echo "  ✗ cc-fleet --check is NOT green (rc=$crc) — read the rows above; the fleet is degraded, not live"; rc=1; fi
  else
    echo "== verdict: cc-fleet not present in $REPO/bin or ~/.claude/bin — the reconciler lands separately."
    echo "   Verify by hand instead:  launchctl print gui/$UID_/<label> | grep -E 'state|runs|last exit'"
  fi
fi

echo
if [ "$rc" -eq 0 ]; then echo "== fleet at declared state =="; else echo "== INCOMPLETE — the fleet is degraded, not live (see ✗ above) ==" >&2; fi
echo "  board:     cc-blockers                  # fleet-inert rows are the floor: one honest verdict per label"
echo "  table:     cc-fleet --table"
echo "  per-label: launchctl print gui/\$(id -u)/<label> | grep -E 'state|runs|last exit'"
echo "  disabled:  launchctl print-disabled gui/\$(id -u) | grep com.claude"
if [ "$rc" -eq 0 ]; then echo "  mark done: touch $SELF_LIVE.done"
else echo "  mark done: NOT YET — reconcile is incomplete; fix the ✗ rows first, re-run (idempotent), then touch $SELF_LIVE.done"; fi
echo "ROLLBACK (per label): launchctl bootout gui/\$(id -u)/<label>   # add: launchctl disable gui/\$(id -u)/<label> to keep it down across reboots"
exit "$rc"
