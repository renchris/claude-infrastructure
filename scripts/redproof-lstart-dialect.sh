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
SUITE="tests/lstart-dialect-bin.bats"
RSUITE="tests/lstart-dialect-registry.bats"

# ── THE ANCHOR TABLE — one source for every literal this harness pins in the CURRENT tree ─────────
# Rows are `id|rule|file|literal`. `--check-anchors` COUNTS them; the mutators and extractors below
# SUBSTITUTE and derive from the same rows via anchor_lit(). ONE table, deliberately: a cheap screen
# that keeps its own copy of the literals can go green while the expensive run is already broken,
# which is the vacuous pass one level up that tests/anti-vacuity-contract.bats exists to prevent.
#
# Only CURRENT-tree literals belong here. The prior-shape needles in ARM 1 and the ex() extractions
# in ARM 2 read the archived PARENT tree, where they are *expected* to be absent from HEAD — an
# anchor check over those would convict this repo for having landed the fix.
#
#   rule=one   must appear EXACTLY once — a single-site substitution; 0 means the proof lost its
#              subject, 2+ means the mutation would sabotage more than it claims.
#   rule=some  must appear at least once — a line FILTER that strips every occurrence.
#   rule=file  the literal is unused; the file must EXIST (a suite this harness runs; a missing one
#              makes tally() print `plan=?`, which reads like a quiet zero rather than a break).
#
# Every mutation below is DERIVED from its anchor by a further literal replace, so the "before" and
# the "after" cannot drift apart either.
ANCHORS=(
  "migration-fallback:cc-backlog|some|bin/cc-backlog|# migration:"
  "migration-fallback:cc-reaper|some|bin/cc-reaper|# migration:"
  "migration-fallback:cc-dispatch|some|bin/cc-dispatch|# migration:"
  "migration-fallback:cc-respawn|some|bin/cc-respawn|# migration:"
  "migration-fallback:cc-pane-headless|some|bin/cc-pane-headless|# migration:"
  "deathwatch-overlay-triple|one|bin/cc-deathwatch-kqueue|for overlay in ({\"TZ\": \"UTC\", \"LC_ALL\": \"C\"}, None, {\"LC_ALL\": \"C\"}):"
  "registry-canonical-write|one|hooks/session-register.sh|lstart=\$(TZ=UTC LC_ALL=C ps -o lstart="
  "registry-norm-order-swap:cc-sessions|one|bin/cc-sessions|    *)           printf '%s %s %s %s %s' \"\$1\" \"\$3\" \"\$2\" \"\$4\" \"\$5\""
  "registry-norm-order-swap:cc-notify|one|bin/cc-notify|    *)           printf '%s %s %s %s %s' \"\$1\" \"\$3\" \"\$2\" \"\$4\" \"\$5\""
  "registry-norm-fn|one|bin/cc-notify|reg_lstart_norm() {"
  "registry-pidlive-fn|one|bin/cc-notify|pid_live() {"
  "suite-bin|file|$SUITE|"
  "suite-registry|file|$RSUITE|"
)

anchor_lit() { # <id> -> its literal. A miss is exit 9 and never an empty string, because an empty
               # FROM makes python's str.replace() match at every position.
  local row r
  for row in "${ANCHORS[@]}"; do
    case "$row" in
      "$1|"*) r="${row#*|}"; r="${r#*|}"; printf '%s' "${r#*|}"; return 0 ;;
    esac
  done
  echo "NO SUCH ANCHOR: $1" >&2
  return 9
}

check_anchors() {
  local live=0 stale=0 row id rule file lit n
  echo "RED-PROOF --check-anchors — every literal this harness pins must still match its subject"
  for row in "${ANCHORS[@]}"; do
    id="${row%%|*}"; row="${row#*|}"
    rule="${row%%|*}"; row="${row#*|}"
    file="${row%%|*}"; lit="${row#*|}"
    if [ "$rule" = file ]; then
      if [ -f "$REPO/$file" ]; then
        live=$((live + 1))
      else
        printf '  STALE ANCHOR %-38s (%s is gone — the arm that runs it would report plan=?)\n' \
          "$id" "$file"
        stale=$((stale + 1))
      fi
      continue
    fi
    # -1 for an unreadable file, so a deleted subject lands in the STALE arm rather than reading 0
    # for rule=one (which is stale anyway) and being indistinguishable from a renamed line.
    n="$(LIT="$lit" /usr/bin/python3 - "$REPO/$file" <<'PY'
import os, sys
try:
    print(open(sys.argv[1]).read().count(os.environ["LIT"]))
except OSError:
    print(-1)
PY
)"
    case "$rule:$n" in
      one:1)          live=$((live + 1)) ;;
      some:0|some:-1) printf '  STALE ANCHOR %-38s (matches %sx in %s — need at least 1)\n' \
                        "$id" "$n" "$file"; stale=$((stale + 1)) ;;
      some:*)         live=$((live + 1)) ;;
      *)              printf '  STALE ANCHOR %-38s (matches %sx in %s — must be exactly 1)\n' \
                        "$id" "$n" "$file"; stale=$((stale + 1)) ;;
    esac
  done
  printf 'RED-PROOF --check-anchors: %d live · %d STALE\n' "$live" "$stale"
  [ "$stale" -eq 0 ]
}

# The cheap half, and it exits BEFORE the parent-sha guard: the anchor check is about THIS tree and
# has no parent to compare against. tests/anti-vacuity-contract.bats runs this mode on every land.
if [ "${1:-}" = "--check-anchors" ]; then
  check_anchors
  exit $?
fi

PARENT="${1:-}"
[ -n "$PARENT" ] || { echo "usage: $0 <parent-sha> | $0 --check-anchors" >&2; exit 2; }
export PATH="/opt/homebrew/bin:$PATH"          # bats is NOT on a hardened PATH; rc 127 reads as red

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
  # Both literals come from the ANCHOR TABLE, and the "after" is DERIVED from the "before" — so
  # --check-anchors and this mutation are pinned to the same string by construction.
  if [ "$2" = "bin/cc-deathwatch-kqueue" ]; then
    LIT="$(anchor_lit deathwatch-overlay-triple)" python3 - "$1/$2" <<'PY'
import os, sys
p = sys.argv[1]
s = open(p).read()
frm = os.environ["LIT"]
# Drop the two fallback overlays, keeping the trailing comma: `(x,)` stays a one-tuple, whereas
# `(x)` would silently iterate the dict's KEYS and mutate something other than what is claimed.
to = frm.replace(', None, {"LC_ALL": "C"}):', ',):')
assert to != frm, "ANCHOR NO LONGER CARRIES THE FALLBACKS: %r" % frm[:70]
new = s.replace(frm, to)
assert new != s, "MUTANT DID NOT APPLY to %s — an absent control, not a pass" % p
open(p, "w").write(new)
PY
  else
    LIT="$(anchor_lit "migration-fallback:$(basename "$2")")" python3 - "$1/$2" <<'PY'
import os, sys
p = sys.argv[1]
s = open(p).read()
mark = os.environ["LIT"]
new = "\n".join(l for l in s.split("\n") if mark not in l)
assert new != s, "MUTANT DID NOT APPLY to %s — an absent control, not a pass" % p
open(p, "w").write(new)
PY
  fi
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
RSITES="hooks/session-register.sh bin/cc-sessions bin/cc-notify"   # RSUITE: set with the anchors

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
  # Function headers come from the ANCHOR TABLE. A rename used to yield an EMPTY extraction, whose
  # `. "$ex"; pid_live …` error was swallowed by the 2>/dev/null below and printed as a blank
  # verdict — a non-verdict wearing a verdict's shape. Now it says so. (reg_lstart_norm is absent
  # from the PARENT by design, so the guard requires a non-empty extraction, never both names.)
  awk -v A="$(anchor_lit registry-norm-fn)" -v B="$(anchor_lit registry-pidlive-fn)" '
       index($0,A)==1{i=1} i{print} i&&/^\}/{i=0}
       index($0,B)==1{j=1} j{print} j&&/^\}/{j=0}' "$tree/bin/cc-notify" > "$ex"
  if [ ! -s "$ex" ]; then
    printf '  %-7s cc-notify pid_live → EXTRACTION EMPTY (anchors stale) — NOT a verdict\n' "$lbl"
    continue
  fi
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
  if [ "$2" = "hooks/session-register.sh" ]; then
    LIT="$(anchor_lit registry-canonical-write)" python3 - "$1/$2" <<'PY'
import os, sys
p = sys.argv[1]
s = open(p).read()
frm = os.environ["LIT"]
to = frm.replace(" LC_ALL=C", "")        # half-pin the write: TZ only, which is the parent's shape
assert to != frm, "ANCHOR NO LONGER PINS THE LOCALE: %r" % frm[:70]
new = s.replace(frm, to)
assert new != s, "MUTANT DID NOT APPLY to %s — an absent control, not a pass" % p
open(p, "w").write(new)
PY
  else
    LIT="$(anchor_lit "registry-norm-order-swap:$(basename "$2")")" python3 - "$1/$2" <<'PY'
import os, sys
p = sys.argv[1]
s = open(p).read()
frm = os.environ["LIT"]
# Neuter the normaliser: make it the identity, which is exactly the parent's behaviour.
to = frm.replace('"$1" "$3" "$2"', '"$1" "$2" "$3"')
assert to != frm, "ANCHOR NO LONGER SWAPS THE ORDER: %r" % frm[:70]
new = s.replace(frm, to)
assert new != s, "MUTANT DID NOT APPLY to %s — an absent control, not a pass" % p
open(p, "w").write(new)
PY
  fi
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
