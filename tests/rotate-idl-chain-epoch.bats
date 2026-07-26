#!/usr/bin/env bats
# rotate-autonomy-logs.sh × cc-idl — the IDL hash-chain EPOCH coupling.
#
# The seam these tests pin: the IDL is rotated (bounded growth) while its tamper-evidence chain
# is append-only and MONOTONIC (that immutability IS the security property). Nobody owned the
# seam — `cc-idl seal` had zero callers — so the chain froze on 2026-07-19 at 6,910 links while
# the IDL rotated three times beneath it, and `cc-idl verify` read the live 136-line IDL against
# that chain and reported 6,791 records "DELETED/TRUNCATED": a PERMANENT FALSE TAMPER. A detector
# stuck ON is strictly worse than no detector — a real tamper becomes indistinguishable from
# routine rotation. These tests hold the fix shut.
#
# Harness laws (mirroring tests/cc-idl.bats §3.10): L1 every chain byte comes from the REAL
# cc-idl, never a hand-rolled hash. L2 every guarantee is proven by its DISCRIMINATOR PAIR — the
# green case AND the case that must go red — so a test that cannot fail is never counted as proof.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  ROT="$REPO/scripts/rotate-autonomy-logs.sh"
  # Hermetic $HOME (test-hermeticity-lint): the subject resolves cc-idl and its default IDL under
  # $HOME, so an unfixtured run would read — and seal — the operator's real autonomy ledger.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_IDL_BIN="$REPO/bin/cc-idl"          # L1: the real sealer, never a stub
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"   # the rotation target AND the chain-epoch subject
  CHAIN="$CC_IDL.chain"
  export ROTATE_MAX_BYTES=100
  export ROTATE_KEEP=3
  export ROTATE_GZIP=0                          # keep archives plain so tests can read them
  command -v perl >/dev/null || skip "perl (Digest::SHA) required by cc-idl"
}

# write N distinct JSON records to the IDL (distinct so a hash chain is meaningful)
mkidl() { # <path> <n>
  local i=1; : > "$1"
  while [ "$i" -le "$2" ]; do printf '{"ts":"2026-07-26T00:00:%02dZ","seq":%d,"kind":"test"}\n' "$((i % 60))" "$i" >> "$1"; i=$((i + 1)); done
}
nl_of() { [ -f "$1" ] && wc -l < "$1" | tr -d ' ' || echo 0; }

# ── (1) THE MISSING CALLER: a run seals. Discriminator = ROTATE_SEAL=0 must NOT seal. ────────
@test "a run seals the IDL tail — the caller cc-idl seal never had" {
  export ROTATE_MAX_BYTES=100000                   # well above the body: seal WITHOUT rotating
  mkidl "$CC_IDL" 5
  run bash "$ROT" "$CC_IDL"
  [ "$status" -eq 0 ]
  [ -s "$CHAIN" ]                                  # the chain now exists because the run made it
  [ "$(nl_of "$CHAIN")" -eq 5 ]                    # all 5 records sealed (the run record is the tail)
  echo "$output" | grep -q 'seal=ok'
}

@test "RED-proof: ROTATE_SEAL=0 leaves the chain unwritten (the pre-fix world)" {
  export ROTATE_MAX_BYTES=100000
  mkidl "$CC_IDL" 5
  ROTATE_SEAL=0 run bash "$ROT" "$CC_IDL"
  [ "$status" -eq 0 ]
  [ ! -e "$CHAIN" ]                                # nothing sealed — proves test 1 measures the wiring
}

@test "sealing is incremental across runs — the chain tracks the job cadence" {
  export ROTATE_MAX_BYTES=100000
  mkidl "$CC_IDL" 3
  bash "$ROT" "$CC_IDL" >/dev/null
  local first; first="$(nl_of "$CHAIN")"
  printf '{"ts":"2026-07-26T00:01:00Z","seq":99,"kind":"later"}\n' >> "$CC_IDL"
  bash "$ROT" "$CC_IDL" >/dev/null
  [ "$(nl_of "$CHAIN")" -gt "$first" ]             # extended, not restarted
  run "$CC_IDL_BIN" verify
  [ "$status" -eq 0 ]
}

# ── (2) THE REGRESSION THIS EXISTS FOR: verify stays GREEN across a rotation ─────────────────
@test "verify is GREEN after a rotation — the false-TAMPER regression is pinned" {
  mkidl "$CC_IDL" 40                               # > 100 bytes → will rotate
  bash "$ROT" "$CC_IDL" >/dev/null
  run "$CC_IDL_BIN" verify
  [ "$status" -eq 0 ]                              # pre-fix this was rc 7, permanently
}

@test "RED-proof: an un-retired chain over a rotated IDL is exactly the rc-7 false TAMPER" {
  mkidl "$CC_IDL" 40
  bash "$ROT" "$CC_IDL" >/dev/null                 # rotates; chain correctly retired
  # Re-create the pre-fix world: put a long chain back over the short live IDL.
  cp "$(ls "$CHAIN".* | head -1)" "$CHAIN"
  run "$CC_IDL_BIN" verify
  [ "$status" -eq 7 ]                              # the bug's signature — so the green test is real
  echo "$output" | grep -q 'DELETED/TRUNCATED'
}

# ── (3) EPOCH MECHANICS: the sidecar retires WITH the body it seals ──────────────────────────
@test "rotation archives the chain at the SAME stamp as the IDL body it seals" {
  mkidl "$CC_IDL" 40
  bash "$ROT" "$CC_IDL" >/dev/null
  local body chain_arch bstamp cstamp
  body="$(ls "$CC_IDL".* | grep -v '\.chain' | head -1)"
  chain_arch="$(ls "$CHAIN".* | head -1)"
  [ -n "$body" ] && [ -n "$chain_arch" ] || false
  bstamp="${body##*.}"; cstamp="${chain_arch##*.}"
  [ "$bstamp" = "$cstamp" ]                        # joined forever, never orphaned
}

@test "the archived pair is INDEPENDENTLY verifiable — evidence survives rotation" {
  mkidl "$CC_IDL" 40
  bash "$ROT" "$CC_IDL" >/dev/null
  local body chain_arch
  body="$(ls "$CC_IDL".* | grep -v '\.chain' | head -1)"
  chain_arch="$(ls "$CHAIN".* | head -1)"
  # The whole point of retiring rather than deleting: the retired epoch still proves itself.
  CC_IDL="$body" CC_IDL_CHAIN="$chain_arch" run "$CC_IDL_BIN" verify
  [ "$status" -eq 0 ]
}

@test "a tampered ARCHIVE is still caught — retirement preserves the guarantee" {
  mkidl "$CC_IDL" 40
  bash "$ROT" "$CC_IDL" >/dev/null
  local body chain_arch
  body="$(ls "$CC_IDL".* | grep -v '\.chain' | head -1)"
  chain_arch="$(ls "$CHAIN".* | head -1)"
  # Rewrite one archived record in place — the classic ledger-lie.
  sed -i.bak '3s/.*/{"ts":"2026-07-26T00:00:03Z","seq":3,"kind":"FORGED"}/' "$body" && rm -f "$body.bak"
  CC_IDL="$body" CC_IDL_CHAIN="$chain_arch" run "$CC_IDL_BIN" verify
  [ "$status" -eq 7 ]
}

@test "the successor epoch opens with a witnessed link back to the retired head" {
  mkidl "$CC_IDL" 40
  bash "$ROT" "$CC_IDL" >/dev/null
  grep -q '"kind":"idl_epoch_close"' "$CC_IDL"
  grep -q '"prev_head":"[0-9a-f]\{64\}"' "$CC_IDL"   # the retired chain's final hash, recorded
  grep -q '"chain_archive":"' "$CC_IDL"
  # …and that record is itself sealed, so the epochs form one continuous chain-of-chains.
  [ "$(nl_of "$CHAIN")" -ge 1 ]
  run "$CC_IDL_BIN" verify
  [ "$status" -eq 0 ]
}

# ── (4) PRUNING: the sidecar is not a rotation of the body ───────────────────────────────────
@test "the live chain survives pruning — it is excluded from the body's KEEP glob" {
  mkidl "$CC_IDL" 5
  bash "$ROT" "$CC_IDL" >/dev/null                 # under threshold → seals only
  [ -s "$CHAIN" ]
  local i=0
  while [ "$i" -lt 5 ]; do                          # force several rotations past KEEP=3
    mkidl "$CC_IDL" 40; bash "$ROT" "$CC_IDL" >/dev/null; i=$((i + 1))
  done
  [ -s "$CHAIN" ]                                   # pre-fix the sidecar sat on the delete list
  run "$CC_IDL_BIN" verify
  [ "$status" -eq 0 ]
}

@test "bodies and chain archives prune to EQUAL depth — no body outlives its proof" {
  local i=0
  while [ "$i" -lt 6 ]; do
    mkidl "$CC_IDL" 40; bash "$ROT" "$CC_IDL" >/dev/null; i=$((i + 1))
  done
  local bodies chains
  bodies="$(ls "$CC_IDL".* 2>/dev/null | grep -vc '\.chain' || true)"
  chains="$(ls "$CHAIN".* 2>/dev/null | grep -vc '\.lock\.d' || true)"
  [ "$bodies" -le "$ROTATE_KEEP" ]
  [ "$chains" -le "$ROTATE_KEEP" ]
  [ "$bodies" -eq "$chains" ]                       # stamp-matched pairs, always
}

# ── (5) THE REPAIR VERB: explicit, recorded, and refusing when it would launder ──────────────
@test "--repair-chain-epoch retires an orphaned chain and RECORDS its head" {
  mkidl "$CC_IDL" 20
  "$CC_IDL_BIN" seal >/dev/null                     # chain now seals 20
  local orphan_head; orphan_head="$(tail -n1 "$CHAIN" | cut -f2)"
  mkidl "$CC_IDL" 2                                 # simulate a pre-wiring rotation: IDL shrank
  run "$CC_IDL_BIN" verify
  [ "$status" -eq 7 ]                               # the orphaned state
  run bash "$ROT" --repair-chain-epoch
  [ "$status" -eq 0 ]
  grep -q '"kind":"idl_epoch_repair"' "$CC_IDL"
  grep -q "\"prev_head\":\"$orphan_head\"" "$CC_IDL"   # retired, NOT discarded
  [ -n "$(ls "$CHAIN".* 2>/dev/null)" ]                # the orphan is archived, not deleted
  run "$CC_IDL_BIN" verify
  [ "$status" -eq 0 ]                                  # the false TAMPER is cleared
}

@test "ANTI-LAUNDER: repair REFUSES when the chain is not orphaned" {
  mkidl "$CC_IDL" 20
  "$CC_IDL_BIN" seal >/dev/null
  # A real tamper: rewrite a sealed line in place. idl length is UNCHANGED, so this is a hash
  # divergence, not a truncation — repair must not be usable to paper over it.
  sed -i.bak '5s/.*/{"ts":"2026-07-26T00:00:05Z","seq":5,"kind":"FORGED"}/' "$CC_IDL" && rm -f "$CC_IDL.bak"
  run bash "$ROT" --repair-chain-epoch
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'REFUSED'
  run "$CC_IDL_BIN" verify
  [ "$status" -eq 7 ]                               # the tamper is still standing, still loud
}

@test "a sweep that does NOT rotate never touches an orphan — no silent laundering" {
  export ROTATE_MAX_BYTES=100000                    # below threshold → seal-only, no rotation
  mkidl "$CC_IDL" 20
  "$CC_IDL_BIN" seal >/dev/null
  mkidl "$CC_IDL" 2                                 # orphaned (chain 20 > idl 2)
  bash "$ROT" "$CC_IDL" >/dev/null                  # an ordinary sweep run
  run "$CC_IDL_BIN" verify
  [ "$status" -eq 7 ]                               # still loud — the sweep must not launder
}

@test "a rotation that retires an ORPHANED chain says so, permanently and on stderr" {
  # Retiring a sidecar necessarily clears the live verify. That is unavoidable (rotation must
  # proceed), so the requirement is that it can never happen QUIETLY: the epoch record carries
  # orphaned:true forever, and the run warns. In production this is nearly unreachable — a
  # truncated IDL is small, and only an oversize file rotates — but it must not be silent.
  mkidl "$CC_IDL" 20
  "$CC_IDL_BIN" seal >/dev/null
  mkidl "$CC_IDL" 2                                 # orphaned, and (at MAX_BYTES=100) oversize
  run bash "$ROT" "$CC_IDL"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'ORPHANED at rotation'   # loud at run time
  grep -q '"orphaned":true' "$CC_IDL"               # and permanently, in the evidence trail
  # the divergence itself is preserved: the archived pair still fails on its own
  local body chain_arch
  body="$(ls "$CC_IDL".* | grep -v '\.chain' | head -1)"
  chain_arch="$(ls "$CHAIN".* | head -1)"
  CC_IDL="$body" CC_IDL_CHAIN="$chain_arch" run "$CC_IDL_BIN" verify
  [ "$status" -eq 7 ]
}

@test "a CLEAN rotation records orphaned:false — the discriminator for the flag" {
  mkidl "$CC_IDL" 40
  run bash "$ROT" "$CC_IDL"
  [ "$status" -eq 0 ]
  grep -q '"orphaned":false' "$CC_IDL"
  ! echo "$output" | grep -q 'ORPHANED at rotation'
}
