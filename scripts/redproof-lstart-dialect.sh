#!/usr/bin/env bash
# Red-proof for backlog 7a00b5de1ec0 — the {pid,lstart} dialect class across the bin/ tools.
#
# Three arms, all printed side by side, because a single green run proves nothing:
#   PRIOR SHAPE  the PARENT tree carries the bare-`ps` readers this fix removes — so the negative
#                control is non-vacuous (it fails because the bug is THERE, not merely because a new
#                symbol is missing).
#   PRE / POST   the new suite against the parent tree and against this tree.
#   MUTANTS      one per site: strip that ONE file's dialect fallbacks and require exactly the tests
#                naming that site to go red. A green suite otherwise credits no site in particular.
#
# Nothing is edited in place: every arm runs in its own `git archive` scratch tree.
set -u

# Resolve $0 through its symlinks BEFORE deriving the root. `~/.claude/scripts/*` are per-file
# symlinks into the checkout, so through the live layer `dirname "$0"/..` is ~/.claude — no tests/,
# no docs/, no .git — and this script would silently red-proof the WRONG TREE. No `readlink -f`:
# that is GNU-only and this box is BSD. Canonical loop: _resolve_self() in scripts/ship-land.sh.
_p="$0"
while [ -L "$_p" ]; do
  _d="$(cd "$(dirname "$_p")" && pwd)"
  _p="$(readlink "$_p")"
  case "$_p" in /*) ;; *) _p="$_d/$_p" ;; esac
done
REPO="$(cd "$(dirname "$_p")/.." && pwd)"
PARENT="${1:-}"
[ -n "$PARENT" ] || { echo "usage: $0 <parent-sha>" >&2; exit 2; }
export PATH="/opt/homebrew/bin:$PATH"          # bats is NOT on a hardened PATH; rc 127 reads as red
SUITE="tests/lstart-dialect-bin.bats"

banner() { printf '\n══ %s\n' "$*"; }

tally() { # <tap-file> <label>
  local f="$1" lbl="$2" plan ok notok skip
  plan="$(sed -n 's/^1\.\.\([0-9]*\)$/\1/p' "$f" | head -1)"
  ok="$(grep -c '^ok ' "$f" 2>/dev/null || true)"
  notok="$(grep -c '^not ok ' "$f" 2>/dev/null || true)"
  skip="$(grep -c '# skip' "$f" 2>/dev/null || true)"
  printf '%-26s plan=%-4s ok=%-4s notok=%-4s skip=%-3s sum=%s\n' \
    "$lbl" "${plan:-?}" "$ok" "$notok" "$skip" "$(( ok + notok ))"
}

# ── ARM 1 — the PARENT carries the PRIOR SHAPE ───────────────────────────────────────────────────
banner "PRIOR SHAPE at parent $PARENT (non-vacuity of the negative control)"
PT="$(mktemp -d)"
git -C "$REPO" archive "$PARENT" | tar -x -C "$PT"
for spec in \
  "bin/cc-backlog:cur_lstart=\"\$(ps -o lstart=" \
  "bin/cc-reaper:proc_lstart(){ ps -o lstart=" \
  "bin/cc-reaper:wd_lstart(){ ps -o lstart=" \
  "bin/cc-dispatch:cur=\"\$(ps -o lstart=" \
  "bin/cc-respawn:pid_start() { ps -o lstart=" \
  "bin/cc-pane-headless:pstart_of() { ps -o lstart=" ; do
  f="${spec%%:*}"; needle="${spec#*:}"
  printf '  %-24s bare-ps reader/writer present: %s\n' "$f" "$(grep -cF "$needle" "$PT/$f" 2>/dev/null || echo 0)"
done
for spec in "bin/cc-backlog:llo_lstart_matches" "bin/cc-reaper:lstart_matches" \
            "bin/cc-reaper:wd_lstart_matches" "bin/cc-respawn:start_is_same" \
            "bin/cc-pane-headless:pstart_matches" "bin/cc-deathwatch-kqueue:start_is_same" ; do
  f="${spec%%:*}"; needle="${spec#*:}"
  printf '  %-24s NEW helper %-22s present: %s\n' "$f" "$needle" \
    "$(grep -cF "$needle" "$PT/$f" 2>/dev/null || echo 0)"
done

# ── ARM 2 — the parent's OWN predicates reject a same-process record written in another dialect ───
banner "BEHAVIOURAL PRE-PROBE — the parent's real predicates, on a REAL live pid"
cat > "$PT/probe.sh" <<'PROBE'
set -u
PT="$1"
sleep 60 & LIVE=$!
STUB="$(mktemp -d)/bin"; mkdir -p "$STUB"
cat > "$STUB/ps" <<'S'
#!/bin/bash
want=""; prev=""
for a in "$@"; do [ "$prev" = "-p" ] && want="$a"; prev="$a"; done
[ "$want" = "$CC_STUB_LIVE_PID" ] || exit 1
if [ "${TZ:-}" = "UTC" ] && [ "${LC_ALL:-}" = "C" ]; then echo 'Fri Aug 21 15:45:00 2026'
elif [ "${LC_ALL:-}" = "C" ]; then echo 'Fri Aug 21 08:45:00 2026'
else echo 'Fri 21 Aug 08:45:00 2026'; fi
S
chmod +x "$STUB/ps"; export PATH="$STUB:$PATH" CC_STUB_LIVE_PID="$LIVE"
# The record is what a LAUNCHD/C-locale producer writes; the probe process reads in ambient.
# Using the reader's OWN dialect here makes even the buggy parent match — the probe could not
# fail, and it reported 'no bug' on every site until this line was corrected.
AMB='Fri Aug 21 08:45:00 2026'

ex() { awk -v F="$2" 'd{next} $0 ~ "^"F"\\(\\) *\\{" && $0 ~ "\\}[[:space:]]*$"{print;d=1;next}
                      $0 ~ "^"F"\\(\\) *\\{"{i=1} i{print} i&&/^\}/{d=1;i=0}' "$PT/$1"; }

eval "$(ex bin/cc-reaper proc_lstart)"; eval "$(ex bin/cc-reaper lock_holder_alive)"
if lock_holder_alive "$LIVE" "$AMB"; then echo "  cc-reaper lock_holder_alive : ALIVE  (no bug)"
else echo "  cc-reaper lock_holder_alive : DEAD   <-- live holder judged dead ⇒ mutex broken"; fi

eval "$(ex bin/cc-reaper wd_lstart)"; eval "$(ex bin/cc-reaper wd_daemon_live)"
if wd_daemon_live "$LIVE" "$AMB"; then echo "  cc-reaper wd_daemon_live    : LIVE   (no bug)"
else echo "  cc-reaper wd_daemon_live    : NOT-OURS <-- tracked daemon ⇒ 'UNTRACKED' ⇒ printed as kill"; fi

eval "$(ex bin/cc-dispatch is_uint)"; eval "$(ex bin/cc-dispatch lock_holder_live)"
LOCK_DIR="$(mktemp -d)"; printf '%s|%s\n' "$LIVE" "$AMB" > "$LOCK_DIR/owner"
if lock_holder_live; then echo "  cc-dispatch lock_holder_live: LIVE   (no bug)"
else echo "  cc-dispatch lock_holder_live: STALE  <-- live holder ⇒ lock broken ⇒ double-claim"; fi

eval "$(ex bin/cc-respawn pid_start)"
if [ "$(pid_start "$LIVE")" = "$AMB" ]; then echo "  cc-respawn verify-stopped   : SAME   (no bug)"
else echo "  cc-respawn verify-stopped   : RECYCLED <-- live session declared stopped ⇒ respawned"; fi

eval "$(ex bin/cc-pane-headless pstart_of)"
if [ "$(pstart_of "$LIVE")" = "$AMB" ]; then echo "  cc-pane-headless is_live    : LIVE   (no bug)"
else echo "  cc-pane-headless is_live    : DEAD   <-- live agent judged dead"; fi

kill "$LIVE" 2>/dev/null
PROBE
bash "$PT/probe.sh" "$PT" 2>/dev/null

# ── ARM 3 — PRE / POST of the suite itself ───────────────────────────────────────────────────────
banner "SUITE — PRE (parent tree) vs POST (this tree)"
cp "$REPO/$SUITE" "$PT/$SUITE"
( cd "$PT" && CC_REDPROOF_TREE="$PT" bats "$SUITE" ) > /tmp/rp-pre.tap 2>&1
( cd "$REPO" && bats "$SUITE" ) > /tmp/rp-post.tap 2>&1
tally /tmp/rp-pre.tap  "PRE  (parent)"
tally /tmp/rp-post.tap "POST (this tree)"
printf '%-26s %s\n' "PRE  BW01 vacuity warns" "$(grep -c BW01 /tmp/rp-pre.tap  || true)"
printf '%-26s %s\n' "POST BW01 vacuity warns" "$(grep -c BW01 /tmp/rp-post.tap || true)"

# ── ARM 4 — PER-SITE MUTANTS ─────────────────────────────────────────────────────────────────────
banner "PER-SITE MUTANTS — each must bite ONLY its own site's tests"
mutate() { # <tree> <file> — strip that file's dialect fallbacks; FAIL LOUD if nothing changed
  python3 - "$1/$2" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
if p.endswith("cc-deathwatch-kqueue"):
    new = s.replace('for overlay in ({"TZ": "UTC", "LC_ALL": "C"}, None, {"LC_ALL": "C"}):',
                    'for overlay in ({"TZ": "UTC", "LC_ALL": "C"},):')
else:
    new = "\n".join(l for l in s.split("\n") if "# migration:" not in l)
assert new != s, "MUTANT DID NOT APPLY to %s — an absent control, not a pass" % p
open(p, "w").write(new)
PY
}
for f in bin/cc-backlog bin/cc-reaper bin/cc-dispatch bin/cc-respawn \
         bin/cc-pane-headless bin/cc-deathwatch-kqueue; do
  MT="$(mktemp -d)"
  git -C "$REPO" archive HEAD | tar -x -C "$MT" 2>/dev/null
  # Overlay the WORKING TREE. `git archive HEAD` is the PARENT while this work is uncommitted,
  # so mutating on top of it measures the absence of every helper, not the mutated site.
  cp "$REPO"/bin/* "$MT/bin/" 2>/dev/null
  cp "$REPO/$SUITE" "$MT/$SUITE"
  mutate "$MT" "$f" || { echo "  MUTANT FAILED TO APPLY: $f"; continue; }
  ( cd "$MT" && CC_REDPROOF_TREE="$MT" bats "$SUITE" ) > "/tmp/rp-mut.tap" 2>&1
  printf '  mutate %-26s → notok=%-3s : %s\n' "$f" \
    "$(grep -c '^not ok ' /tmp/rp-mut.tap || true)" \
    "$(grep '^not ok ' /tmp/rp-mut.tap | sed 's/^not ok [0-9]* //' | cut -c1-46 | paste -sd'; ' -)"
done
