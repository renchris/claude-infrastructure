#!/usr/bin/env bats
#
# headless-address-consumers — THE CONSUMER HALF of backlog 5d1b5dd9b3db.
#
# WHAT THIS PINS, AND WHY IT IS NOT A GREP.
# `bin/cc-pane-headless:124` mints `hdl-<16 hex>` and `:197` runs the agent under
# `export CC_PANE_ID="$id" && unset ITERM_SESSION_ID`. b532c67ec fixed the WRITER
# (hooks/session-register.sh) so that address gets a registry row at all, and the drain hook
# (hooks/mailbox-drain.sh:111-115) so the row is not merely deaf. Every OTHER organ that reads a
# pane address still spelled the rule `*[!0-9A-Fa-f-]*` — "hex and dashes only" — and `h` and `l`
# are not hex digits, so each one silently reclassified a live headless session as unaddressable.
#
# THE ASSERTION IS SEMANTIC, NOT TEXTUAL. For every `case` block in the subject files whose subject
# is a pane address, the real arm list is EXTRACTED FROM THE SHIPPED FILE and replayed against three
# probe values. The property is:
#
#     a headless address must be classified by the SAME arm as a canonical pane uuid,
#     and by a DIFFERENT arm than a path-traversal string.
#
# That is the property the guard actually exists to enforce ("this value becomes $DIR/$pane.json"),
# stated without naming any spelling — so it survives the next re-spelling, and it cannot be greened
# by a comment (memory: denylist-enumerates-spellings-not-the-class, and the weakness #33 named in
# its own falsifier for 4b9d5e93b40a).
#
# RED-PROOF DISCIPLINE (memory: red-proof-fixture-must-not-call-the-subject). The address is written
# out LITERALLY below; nothing here invokes cc-pane-headless, sources a lib the fix touches, or
# calls any symbol the fix introduces. There is no `skip` in any case whose job is to fail pre-fix —
# bats renders a skipped case as `ok`, which is how a vacuous suite reports 5/5 green.
#
# The block census is asserted per file (`[ "$n" -eq <expected> ]`): if a subject file is refactored
# so the extractor finds nothing, this suite goes RED rather than silently testing zero blocks
# (memory: absent-range-endpoint-selects-everything — a stale anchor does not fail, it inverts).

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMP="$BATS_TEST_TMPDIR"
  # A fixtured HOME — nothing here may read or write the operator's live layer.
  export HOME="$TMP/home"; mkdir -p "$HOME/.claude"
  # …and a fixtured HOME is NOT sufficient on its own. cc-recover-safeguard (exercised for real
  # below) reaches its helpers by BARE NAME, so without these two seams it would execute the
  # operator's DEPLOYED cc-notify and cc-sessions off their PATH — pointing both at absent paths is
  # the right fixture, since these sensors fail open on one (scripts/test-hermeticity-lint.sh 5b;
  # the same hole tests/cc-relogin-status.bats had while looking perfectly hermetic).
  export CC_RECOVER_NOTIFY_BIN="$TMP/absent-cc-notify"
  export CC_RECOVER_SESSIONS_BIN="$TMP/absent-cc-sessions"
  export CC_RECOVER_REG_DIR="$TMP/reg" CC_FIRED_DIR="$TMP/fired"
  # This suite names handoff-fire only to EXTRACT text from it and never fires; pin the capacity
  # gate anyway so it can never go red-by-machine-load rather than by its subject.
  export CC_FIRE_CAPACITY_GATE=off

  # The three probe values, written out literally.
  #  HDL   the address bin/cc-pane-headless:124 mints (`hdl-` + 16 hex)
  #  UUID  a canonical iTerm2 pane uuid — the shape every one of these guards was written for
  #  EVIL  a path-traversal string — the thing the guard actually exists to refuse
  HDL="hdl-a1b2c3d4e5f60718"
  UUID="AAAAAAAA-1111-2222-3333-444444444444"
  EVIL="../../etc/passwd"
}

# ── the extractor ────────────────────────────────────────────────────────────────────────────────
# Pulls every `case "$<var>" in … esac` block out of the REAL file and re-emits each one with every
# arm body replaced by "record which arm index matched". Replaying the shipped artifact rather than
# a retyped copy is what keeps this assertion alive after the subject moves
# (memory: control-must-replay-the-real-artifact).
armprobe() { # <file> <var> <value> → prints one line per block: the 1-based index of the arm that
             # matched, or 0 for fall-through. Prints nothing and returns 1 if no block was found.
  local f="$1" v="$2" val="$3" gen
  gen="$TMP/gen.$$.sh"
  SUBJ_FILE="$ROOT/$f" SUBJ_VAR="$v" GEN="$gen" python3 - <<'PY' || return 1
import os, re, sys

src  = open(os.environ["SUBJ_FILE"]).read().split("\n")
var  = os.environ["SUBJ_VAR"]
head = re.compile(r'case\s+"?\$\{?' + re.escape(var) + r'\}?"?\s+in\b')

def arm_patterns(body):
    """Split a case body into arm PATTERNS. Arms here are `PATTERN) body ;;`; a `)` inside a
    bracket expression (`*[!0-9A-Fa-f-]*`) is not an arm terminator, so track bracket depth."""
    pats, chunks = [], body.split(";;")
    for ch in chunks:
        # strip comments (no pattern in these files contains '#') and blank filler
        ch = "\n".join(re.sub(r'#.*$', '', ln) for ln in ch.split("\n")).strip()
        if not ch:
            continue
        depth, cut = 0, -1
        for i, c in enumerate(ch):
            if c == "[":
                depth += 1
            elif c == "]":
                depth -= 1
            elif c == ")" and depth <= 0:
                cut = i
                break
        if cut < 0:
            continue
        p = ch[:cut].strip()
        if p:
            pats.append(p)
    return pats

blocks = []
i = 0
while i < len(src):
    m = head.search(src[i])
    if not m:
        i += 1
        continue
    rest = src[i][m.end():]
    e = re.search(r'\besac\b', rest)
    if e:
        body = rest[:e.start()]
        i += 1
    else:
        buf, j = [rest], i + 1
        while j < len(src) and not re.match(r'^\s*esac\b', src[j]):
            buf.append(src[j])
            j += 1
        # An unterminated block means the file no longer has the shape this extractor models —
        # fail LOUD rather than testing a truncated arm list.
        assert j < len(src), "no esac closes the %s block at %s:%d" % (var, os.environ["SUBJ_FILE"], i + 1)
        body = "\n".join(buf)
        i = j + 1
    p = arm_patterns(body)
    assert p, "block at %s:%d parsed to ZERO arms" % (os.environ["SUBJ_FILE"], i)
    blocks.append(p)

out = []
for pats in blocks:
    out.append('__M=0')
    out.append('case "$SUBJ" in')
    for n, p in enumerate(pats, 1):
        out.append('  %s) __M=%d ;;' % (p, n))
    out.append('esac')
    out.append('printf "%s\\n" "$__M"')
open(os.environ["GEN"], "w").write("\n".join(out) + "\n")
sys.exit(0 if blocks else 1)
PY
  SUBJ="$val" bash "$gen"
}

# classify <file> <var> — prints "<uuid-arms>|<hdl-arms>|<evil-arms>" as three space-joined lists.
classify() {
  local f="$1" v="$2" a b c
  a="$(armprobe "$f" "$v" "$UUID" | tr '\n' ' ')"
  b="$(armprobe "$f" "$v" "$HDL"  | tr '\n' ' ')"
  c="$(armprobe "$f" "$v" "$EVIL" | tr '\n' ' ')"
  printf '%s|%s|%s' "$a" "$b" "$c"
}

# assert_site <file> <var> <expected-block-count>
assert_site() {
  local f="$1" v="$2" want="$3" got n
  got="$(classify "$f" "$v")"
  n="$(armprobe "$f" "$v" "$UUID" | grep -c . || true)"
  # The census guard: a refactor that hides the blocks must RED, never silently test nothing.
  [ "$n" -eq "$want" ] || { echo "BLOCK CENSUS: $f \$$v found $n, expected $want" >&2; return 1; }
  local uuid_arms="${got%%|*}" rest="${got#*|}"
  local hdl_arms="${rest%%|*}" evil_arms="${rest##*|}"
  echo "  $f \$$v  uuid=[$uuid_arms] hdl=[$hdl_arms] evil=[$evil_arms]" >&2
  # (1) THE ROW: a headless address must be treated exactly as a pane uuid is.
  [ "$hdl_arms" = "$uuid_arms" ] || {
    echo "REFUSED: $f \$$v classifies the headless address differently from a pane uuid" >&2; return 1; }
  # (2) THE CONTROL, in the other direction: widening must NOT admit a path fragment.
  [ "$evil_arms" != "$uuid_arms" ] || {
    echo "OVER-WIDE: $f \$$v now admits a path-traversal string" >&2; return 1; }
}

@test "consumers: bin/cc-classify fired_peer accepts a headless address" {
  assert_site bin/cc-classify pane 1
}

@test "consumers: bin/cc-reaper's three stamp readers accept a headless address" {
  assert_site bin/cc-reaper pane 3
}

@test "consumers: bin/cc-reconcile does not count a headless session as pane-less" {
  assert_site bin/cc-reconcile pane 1
}

@test "consumers: bin/cc-recover-safeguard accepts a headless pane argument" {
  assert_site bin/cc-recover-safeguard BLOCKED 1
}

@test "consumers: hooks/mailbox-wake-arm.sh keeps a headless address as the arm target" {
  assert_site hooks/mailbox-wake-arm.sh _pane 1
}

@test "consumers: hooks/session-continue.sh wake floor + mail fold accept a headless address" {
  assert_site hooks/session-continue.sh _ouid 4
}

@test "consumers: hooks/session-continue.sh adopts a headless resolved mailbox key" {
  assert_site hooks/session-continue.sh _rk 1
}

@test "consumers: scripts/desk-invariant.sh reads a headless fired stamp" {
  assert_site scripts/desk-invariant.sh pane 1
}

@test "consumers: scripts/handoff-fire.sh mark_fired_peer stamps a headless peer" {
  assert_site scripts/handoff-fire.sh pane 1
}

@test "consumers: scripts/lead-supervisor.sh sweeps a headless fired peer" {
  assert_site scripts/lead-supervisor.sh pane 1
}

# ── behavioural cases — the two ends of the chain, run for real ──────────────────────────────────

@test "behaviour: cc-recover-safeguard does not reject a headless pane as 'must be a pane UUID'" {
  # The CLI is the cheapest end-to-end proof that the widening reaches a real invocation. It will
  # fail later for want of a registry row; what must NOT happen is the exit-2 shape refusal.
  run env HOME="$HOME" CC_RECOVER_REG_DIR="$TMP/reg" CC_FIRED_DIR="$TMP/fired" \
      bash "$ROOT/bin/cc-recover-safeguard" "$HDL" --dry-run
  [[ "$output" != *"must be a pane UUID"* ]]
}

# cc-notify has no --resolve flag, so resolve() is lifted OUT of the shipped file and called
# directly — the same replay-the-real-artifact rule as the arm extractor above. The two registry
# helpers it calls are stubbed to "no name match / no prefix match", which is the state a fixtured
# registry is actually in; what is under test is the address-shape road resolve() takes on its own.
notify_resolve() { # <target> → stdout: the resolved address; exit: resolve()'s own rc
  local target="$1" gen="$TMP/resolve.$$.sh"
  SUBJ_FILE="$ROOT/bin/cc-notify" GEN="$gen" python3 - <<'PY'
import os, re, sys
src = open(os.environ["SUBJ_FILE"]).read().split("\n")
start = next((i for i, l in enumerate(src) if re.match(r'^resolve\(\)\s*\{', l)), None)
assert start is not None, "ANCHOR MISSING: bin/cc-notify has no top-level resolve() {"
end = next((j for j in range(start + 1, len(src)) if src[j] == "}"), None)
assert end is not None, "ANCHOR MISSING: resolve() is not closed by a column-0 }"
open(os.environ["GEN"], "w").write("\n".join(src[start:end + 1]) + "\n")
PY
  # shellcheck disable=SC1090
  bash -c '
    REG_DIR="'"$TMP/reg"'"
    registry_name_to_uuid(){ return 1; }
    registry_prefix_to_uuid(){ return 2; }
    . "'"$gen"'"
    resolve "'"$target"'"
  '
}

@test "behaviour: cc-notify resolves a headless address that owns a registry row" {
  # resolve() already carries a NON-UUID arm — kitty's decimal pane ids (its 1b, added 2026-08-07)
  # resolve IFF their registry row file exists. A headless id is the same class of address from the
  # same id space, so it takes the same road: row-backed ⇒ resolvable, no row ⇒ still unknown.
  mkdir -p "$TMP/reg"
  printf '{"paneUUID":"%s","name":"hl-agent","pid":%s}' "$HDL" "$$" > "$TMP/reg/$HDL.json"
  run notify_resolve "$HDL"
  [ "$status" -eq 0 ]
  [ "$output" = "$HDL" ]
}

@test "control: a headless address with NO registry row is still UNKNOWN, not invented" {
  # The widening must buy addressability for sessions that registered, not fabricate one for an
  # address nothing has ever claimed — the same dead-row semantics the kitty-int arm already has.
  mkdir -p "$TMP/reg"
  run notify_resolve "hdl-ffffffffffffffff"
  [ "$status" -ne 0 ]
}
