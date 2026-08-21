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

# ── --check-anchors: the half of this harness cheap enough to live in the normal test contract ────
#
# WHY THIS MODE EXISTS. tests/anti-vacuity-contract.bats holds that a red-proof harness which
# nothing runs has rotted into a comment, and its CENSUS makes membership a GLOB — so this file was
# in scope on the day it was written. The full run cannot be that wiring: it needs a parent sha, a
# `git archive` per arm, a bats run per mutant, and a real live pid. What it CAN be is the same
# trade the three sibling harnesses already make — the expensive half stays an explicit invocation,
# and the cheap half, which needs no bats and no git, becomes unconditional.
#
# WHAT IT CHECKS, and the predicate for each class. Every arm below is only as good as a literal
# still matching its subject in THIS tree; when one stops matching, the arm keeps printing and stops
# meaning anything, which is precisely the silent vacuity the contract is about.
#
#   MUTANT  the literal an ARM-4/5e mutator replaces. 0 matches ⇒ `assert new != s` fires and that
#           site becomes an ABSENT CONTROL — the one failure mode a green suite cannot show you.
#   FIX     a symbol this fix introduced. ARM 1 reports it as absent from the PARENT; if it is also
#           absent HERE, the line is reporting on a symbol nothing defines any more.
#   PROBE   a function definition ARM 5b awk-extracts from THIS tree. 0 matches ⇒ the extraction is
#           empty and the arm prints a failure that reads like a verdict.
#   SUITE   a bats file ARMs 3/5d tally. Absent ⇒ the tally is of an empty run.
#
# NOT COVERED, stated rather than implied: a subject that keeps every anchored line and breaks the
# behaviour some other way. Only the full run catches that, and its name is in the failure message.
#
# COUPLING. The MUTANT needles are duplicated between CASES here and the mutate()/rmutate() bodies
# far below — the same convention the sibling harnesses run on. Change one, change the other; the
# mutators' own `assert new != s` is the backstop that makes a missed edit loud rather than silent.
if [ "${1:-}" = "--check-anchors" ]; then
  CC_RP_REPO="$REPO" python3 - <<'PY'
import os, sys

REPO = os.environ["CC_RP_REPO"]

NORM = "    *)           printf '%s %s %s %s %s' \"$1\" \"$3\" \"$2\" \"$4\" \"$5\""
KQ_OVERLAY = 'for overlay in ({"TZ": "UTC", "LC_ALL": "C"}, None, {"LC_ALL": "C"}):'
MIG = "# migration:"

# (id, relative path, class, needle | None, spec)   spec: "1" = exactly once · "+" = at least once
# A needle starting with "^" is matched at line start instead of as a free substring.
CASES = [
    # ── ARM 4 — mutate() strips these; each is one site's negative control ──
    ("cc-backlog-dialect-fallbacks",       "bin/cc-backlog",           "MUTANT", MIG,        "+"),
    ("cc-reaper-dialect-fallbacks",        "bin/cc-reaper",            "MUTANT", MIG,        "+"),
    ("cc-dispatch-dialect-fallbacks",      "bin/cc-dispatch",          "MUTANT", MIG,        "+"),
    ("cc-respawn-dialect-fallbacks",       "bin/cc-respawn",           "MUTANT", MIG,        "+"),
    ("cc-pane-headless-dialect-fallbacks", "bin/cc-pane-headless",     "MUTANT", MIG,        "+"),
    ("kqueue-overlay-tuple",               "bin/cc-deathwatch-kqueue", "MUTANT", KQ_OVERLAY, "1"),
    # ── ARM 5e — rmutate() replaces these; the registry triple's negative controls ──
    ("register-canonical-write",           "hooks/session-register.sh", "MUTANT",
     "lstart=$(TZ=UTC LC_ALL=C ps -o lstart=", "1"),
    ("cc-sessions-order-normaliser",       "bin/cc-sessions",          "MUTANT", NORM,       "1"),
    ("cc-notify-order-normaliser",         "bin/cc-notify",            "MUTANT", NORM,       "1"),
    # ── ARM 1 / 5a — the symbols whose absence-at-the-parent is the non-vacuity claim ──
    ("cc-backlog-new-helper",              "bin/cc-backlog",           "FIX", "llo_lstart_matches", "+"),
    ("cc-reaper-new-helper",               "bin/cc-reaper",            "FIX", "lstart_matches",     "+"),
    ("cc-reaper-wd-new-helper",            "bin/cc-reaper",            "FIX", "wd_lstart_matches",  "+"),
    ("cc-respawn-new-helper",              "bin/cc-respawn",           "FIX", "start_is_same",      "+"),
    ("cc-pane-headless-new-helper",        "bin/cc-pane-headless",     "FIX", "pstart_matches",     "+"),
    ("kqueue-new-helper",                  "bin/cc-deathwatch-kqueue", "FIX", "start_is_same",      "+"),
    ("cc-sessions-new-helper",             "bin/cc-sessions",          "FIX", "reg_lstart_norm",    "+"),
    ("cc-notify-new-helper",               "bin/cc-notify",            "FIX", "reg_lstart_norm",    "+"),
    # ── ARM 5b — the two definitions its awk lifts out of THIS tree's cc-notify ──
    ("cc-notify-pid_live-def",             "bin/cc-notify",            "PROBE", "^pid_live() {",        "1"),
    ("cc-notify-reg_lstart_norm-def",      "bin/cc-notify",            "PROBE", "^reg_lstart_norm() {", "1"),
    # ── ARMs 3 / 5d — the suites the PRE/POST tallies run ──
    ("bin-suite",      "tests/lstart-dialect-bin.bats",      "SUITE", None, "1"),
    ("registry-suite", "tests/lstart-dialect-registry.bats", "SUITE", None, "1"),
]

# This harness's OWN floors, so a gutted table cannot pass by having nothing to check. The suite
# asserts outer floors too; these are the ones that travel with the file.
assert len(CASES) >= 18, "CASES gutted: %d" % len(CASES)
assert sum(1 for c in CASES if c[2] == "MUTANT") >= 9, "every mutation site must be anchored"

bad = 0
for name, rel, kind, needle, spec in CASES:
    path = os.path.join(REPO, rel)
    if not os.path.exists(path):
        print("  STALE ANCHOR %-34s %s is MISSING — the arm reading it cannot mean anything"
              % (name, rel))
        bad += 1
        continue
    if needle is None:
        continue
    text = open(path, encoding="utf-8", errors="replace").read()
    if needle.startswith("^"):
        hits = sum(1 for line in text.split("\n") if line.startswith(needle[1:]))
    else:
        hits = text.count(needle)
    ok = hits >= 1 if spec == "+" else hits == 1
    if not ok:
        want = "at least 1" if spec == "+" else "exactly 1"
        print("  STALE ANCHOR %-34s [%s] MATCHED %dx in %s (need %s)"
              % (name, kind, hits, rel, want))
        bad += 1

if bad:
    print("redproof-lstart-dialect --check-anchors: FAIL — %d of %d anchors no longer match their "
          "subject." % (bad, len(CASES)))
    sys.stderr.write("The proof is stale: re-anchor it, or the arms it backs are unproven. "
                     "Full run: scripts/redproof-lstart-dialect.sh <parent-sha>\n")
    sys.exit(1)

subjects = len({c[1] for c in CASES})
print("redproof-lstart-dialect --check-anchors: %d/%d anchors live across %d subjects. "
      "(Cheap half: proves no arm went vacuous.)" % (len(CASES), len(CASES), subjects))
PY
  exit $?
fi

PARENT="${1:-}"
[ -n "$PARENT" ] || { echo "usage: $0 <parent-sha> | $0 --check-anchors" >&2; exit 2; }
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

# ══════════════════════════════════════════════════════════════════════════════════════════════════
# ARM 5 — THE cc-registry TRIPLE (backlog bb9f69a6a2fa)
#
# Same class, different store, and NOT the same fix. The bin/ sites above were cured by re-rendering
# in each candidate dialect. That cannot work here: both registry readers are reached from launchd
# jobs which export LC_ALL=C, and under an exported LC_ALL a `TZ=UTC ps` overrides only TZ — the
# ambient rendering is unreachable, so a reader cannot reconstruct the writer's environment. Both
# dialects in this store share TZ=UTC and differ only in field ORDER, so the readers normalise the
# ORDER instead. This arm proves the parent is wrong, the fix is right, and the fix still convicts.
# ══════════════════════════════════════════════════════════════════════════════════════════════════
RSUITE="tests/lstart-dialect-registry.bats"
RSITES="hooks/session-register.sh bin/cc-sessions bin/cc-notify"

banner "REGISTRY 5a — PRIOR SHAPE at parent $PARENT (non-vacuity)"
for f in $RSITES; do
  half="$(grep -c 'TZ=UTC ps -o lstart=' "$PT/$f" 2>/dev/null || true)"
  newh="$(grep -c 'reg_lstart_norm' "$PT/$f" 2>/dev/null || true)"
  printf '  %-34s parent half-pinned(TZ only)=%-3s parent new-helper=%s\n' "$f" "${half:-0}" "${newh:-0}"
done
printf '  %-34s %s\n' "parent canonical writes" \
  "$(grep -c 'TZ=UTC LC_ALL=C ps -o lstart=' "$PT/hooks/session-register.sh" 2>/dev/null || true)"

banner "REGISTRY 5b — the PARENT's OWN pid_live, real live pid, C-locale reader"
sleep 60 & RP=$!
CANON_NOW="$(TZ=UTC LC_ALL=C ps -o lstart= -p "$RP" | tr -s ' ' | sed 's/^ *//;s/ *$//')"
# Derive the store's dialect from the canonical string by ORDER, not by re-rendering: the box this
# runs on need not have en_CA generated, and off-box it certainly does not.
# shellcheck disable=SC2086  # the split into five fields IS the operation; quoting defeats it
STORE_NOW="$(set -- $CANON_NOW; printf '%s %s %s %s %s' "$1" "$3" "$2" "$4" "$5")"
printf '  canonical (what a C reader renders) : [%s]\n' "$CANON_NOW"
printf '  stored    (what a session wrote)    : [%s]\n' "$STORE_NOW"
for TREE_LBL in "PARENT:$PT" "THIS:$REPO"; do
  lbl="${TREE_LBL%%:*}"; tree="${TREE_LBL#*:}"
  ex="$(mktemp)"
  awk '/^reg_lstart_norm\(\) *\{/{i=1} i{print} i&&/^\}/{i=0}
       /^pid_live\(\) *\{/{j=1}       j{print} j&&/^\}/{j=0}' "$tree/bin/cc-notify" > "$ex"
  v="$(LC_ALL=C LANG=C bash -c '. "$1"; pid_live "$2" "$3" && echo LIVE || echo "NOT-THE-PEER"' \
        _ "$ex" "$RP" "$STORE_NOW" 2>/dev/null)"
  printf '  %-7s cc-notify pid_live(live pid, stored record) → %s\n' "$lbl" "$v"
done

banner "REGISTRY 5c — the PARENT's cc-sessions BINARY, end to end, C-locale reader"
for TREE_LBL in "PARENT:$PT" "THIS:$REPO"; do
  lbl="${TREE_LBL%%:*}"; tree="${TREE_LBL#*:}"
  rd="$(mktemp -d)"
  printf '{"paneUUID":"AAAAAAAA-1111-2222-3333-444444444444","name":"probe","cwd":"/tmp","account":"next","pid":%s,"startedAt":1,"surface":"headless","lstart":"%s"}\n' \
    "$RP" "$STORE_NOW" > "$rd/AAAAAAAA-1111-2222-3333-444444444444.json"
  n="$(env CC_REGISTRY_DIR="$rd" IT2_BIN=/nonexistent-it2 LC_ALL=C LANG=C \
        "$tree/bin/cc-sessions" --names 2>/dev/null | grep -c . || true)"
  printf '  %-7s live rows visible to a launchd reader = %s   (1 = the live session is addressable)\n' "$lbl" "${n:-0}"
done
kill "$RP" 2>/dev/null || true

banner "REGISTRY 5d — SUITE PRE (parent tree) vs POST (this tree)"
cp "$REPO/$RSUITE" "$PT/$RSUITE"
( cd "$PT"   && CC_REDPROOF_TREE="$PT" bats "$RSUITE" ) > /tmp/rp-reg-pre.tap  2>&1
( cd "$REPO" && bats "$RSUITE" )                        > /tmp/rp-reg-post.tap 2>&1
tally /tmp/rp-reg-pre.tap  "PRE  (parent)"
tally /tmp/rp-reg-post.tap "POST (this tree)"
printf '%-26s %s\n' "PRE  BW01 vacuity warns" "$(grep -c BW01 /tmp/rp-reg-pre.tap  || true)"
printf '%-26s %s\n' "POST BW01 vacuity warns" "$(grep -c BW01 /tmp/rp-reg-post.tap || true)"

banner "REGISTRY 5e — PER-SITE MUTANTS (each must bite ONLY its own site)"
rmutate() { # <tree> <file>
  python3 - "$1/$2" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
if p.endswith("session-register.sh"):
    new = s.replace("lstart=$(TZ=UTC LC_ALL=C ps -o lstart=", "lstart=$(TZ=UTC ps -o lstart=")
else:
    # Neuter the normaliser: make it the identity, which is exactly the parent's behaviour.
    new = s.replace('    *)           printf \'%s %s %s %s %s\' "$1" "$3" "$2" "$4" "$5"',
                    '    *)           printf \'%s %s %s %s %s\' "$1" "$2" "$3" "$4" "$5"')
assert new != s, "MUTANT DID NOT APPLY to %s — an absent control, not a pass" % p
open(p, "w").write(new)
PY
}
for f in $RSITES; do
  MT="$(mktemp -d)"
  git -C "$REPO" archive HEAD | tar -x -C "$MT" 2>/dev/null
  cp "$REPO"/bin/* "$MT/bin/" 2>/dev/null
  cp "$REPO"/hooks/session-register.sh "$MT/hooks/" 2>/dev/null
  cp "$REPO/$RSUITE" "$MT/$RSUITE"
  rmutate "$MT" "$f" || { echo "  MUTANT FAILED TO APPLY: $f"; continue; }
  ( cd "$MT" && CC_REDPROOF_TREE="$MT" bats "$RSUITE" ) > /tmp/rp-reg-mut.tap 2>&1
  printf '  mutate %-30s → notok=%-3s : %s\n' "$f" \
    "$(grep -c '^not ok ' /tmp/rp-reg-mut.tap || true)" \
    "$(grep '^not ok ' /tmp/rp-reg-mut.tap | sed 's/^not ok [0-9]* //' | cut -c1-44 | paste -sd'; ' -)"
done
