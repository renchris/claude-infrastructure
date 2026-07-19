#!/usr/bin/env bats
# rotate-autonomy-logs.sh — size-gated `create`-mode rotation for the unbounded append-only
# autonomy/audit logs (idl.jsonl + bash-commands.log + bash-execution.log). Rename fat file
# aside → recreate empty in place (the per-line `>>` writers reopen the path, zero data loss)
# → gzip the rotated copy → prune to ROTATE_KEEP. Every assertion derives its expected value
# from the script's contract, never from the script's own output.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  ROT="$REPO/scripts/rotate-autonomy-logs.sh"
  export CC_IDL="$BATS_TEST_TMPDIR/idl-audit.jsonl"   # isolated audit sink (NOT a target)
  export ROTATE_MAX_BYTES=100                          # tiny threshold for deterministic tests
  export ROTATE_KEEP=3
  T="$BATS_TEST_TMPDIR/target.log"
}

# make a file of exactly N bytes of 'a'
mkbytes() { # <path> <n>
  head -c "$2" < /dev/zero | tr '\0' 'a' > "$1"
}
# count rotations that exist for a target path
rot_count() { # <path>
  local n=0 g
  for g in "$1".*; do [ -e "$g" ] && n=$((n + 1)); done
  echo "$n"
}

# ── under threshold → left untouched, counted as skipped, one audit record rotated=0 ──
@test "file under ROTATE_MAX_BYTES is not rotated" {
  mkbytes "$T" 50                       # 50 < 100 → under
  run bash "$ROT" "$T"
  [ "$status" -eq 0 ]
  [ -f "$T" ]                           # still there
  [ "$(wc -c < "$T" | tr -d ' ')" -eq 50 ]   # untouched (byte-identical size)
  [ "$(rot_count "$T")" -eq 0 ]         # no rotation produced
  grep -q '"tool":"rotate-autonomy-logs"' "$CC_IDL"
  grep -q '"rotated":0' "$CC_IDL"
  grep -q '"skipped":1' "$CC_IDL"
}

# ── over threshold → moved aside + gzipped, fresh empty file recreated in place ──
@test "file at/over ROTATE_MAX_BYTES rotates: gz produced, live file recreated empty" {
  mkbytes "$T" 250                      # 250 >= 100 → over
  run bash "$ROT" "$T"
  [ "$status" -eq 0 ]
  [ -f "$T" ]                           # recreated in place (readers/writers always see the path)
  [ "$(wc -c < "$T" | tr -d ' ')" -eq 0 ]     # ...and it is EMPTY (fresh)
  [ "$(rot_count "$T")" -eq 1 ]         # exactly one rotation
  ls "$T".*.gz >/dev/null 2>&1          # it is gzipped
  grep -q '"rotated":1' "$CC_IDL"
  grep -q "\"file\":\"$(basename "$T")\",\"bytes\":250" "$CC_IDL"   # audit records the pre-rotation size
}

# ── NO DATA LOSS: rotated bytes survive in the .gz; a subsequent writer append lands fresh ──
@test "rotated content is preserved in .gz and the writer contract continues" {
  # 12 JSONL lines, > 100 bytes → will rotate
  for i in $(seq 1 12); do echo "{\"n\":$i,\"pad\":\"aaaaaaaaaa\"}" >> "$T"; done
  before="$(wc -c < "$T" | tr -d ' ')"
  [ "$before" -ge 100 ]
  run bash "$ROT" "$T"
  [ "$status" -eq 0 ]
  # the archived copy holds the ORIGINAL 12 lines verbatim
  gz="$(ls "$T".*.gz)"
  [ "$(gzip -cd "$gz" | wc -l | tr -d ' ')" -eq 12 ]
  gzip -cd "$gz" | grep -q '{"n":1,'
  gzip -cd "$gz" | grep -q '{"n":12,'
  # simulate the live writer's next `>>` — it must land in the fresh file, not the archive
  echo '{"n":13,"post":"rotation"}' >> "$T"
  [ "$(wc -l < "$T" | tr -d ' ')" -eq 1 ]
  grep -q '{"n":13,' "$T"
}

# ── file mode is preserved across recreate ──
@test "recreated file preserves the original mode" {
  mkbytes "$T" 250
  chmod 600 "$T"
  run bash "$ROT" "$T"
  [ "$status" -eq 0 ]
  mode="$(stat -f '%Lp' "$T" 2>/dev/null || stat -c '%a' "$T")"
  [ "$mode" = "600" ]
}

# ── prune keeps only the newest ROTATE_KEEP rotations ──
@test "prune bounds history to ROTATE_KEEP" {
  # pre-seed 5 OLD rotations (year 2020 stamps sort oldest); KEEP=3
  for s in 20200101T000000Z 20200102T000000Z 20200103T000000Z 20200104T000000Z 20200105T000000Z; do
    echo old > "$T.$s.gz"
  done
  mkbytes "$T" 250                      # over threshold → adds a 6th (newest) rotation, then prunes
  run bash "$ROT" "$T"
  [ "$status" -eq 0 ]
  [ "$(rot_count "$T")" -eq 3 ]         # exactly KEEP survive
  # the just-created (newest) rotation must be among the survivors; the oldest must be gone
  [ ! -e "$T.20200101T000000Z.gz" ]
  ls "$T".*.gz >/dev/null 2>&1
}

# ── ROTATE_GZIP=0 leaves the rotated copy uncompressed ──
@test "ROTATE_GZIP=0 keeps the rotation plain" {
  mkbytes "$T" 250
  ROTATE_GZIP=0 run bash "$ROT" "$T"
  [ "$status" -eq 0 ]
  [ "$(rot_count "$T")" -eq 1 ]
  ! ls "$T".*.gz >/dev/null 2>&1        # NOT gzipped
}

# ── a missing target is a skip, never an error ──
@test "missing target is skipped cleanly" {
  run bash "$ROT" "$BATS_TEST_TMPDIR/does-not-exist.log"
  [ "$status" -eq 0 ]
  grep -q '"skipped":1' "$CC_IDL"
  grep -q '"rotated":0' "$CC_IDL"
}

# ── multiple targets, mixed sizes → rotate the big one only ──
@test "mixed targets rotate independently by size" {
  big="$BATS_TEST_TMPDIR/big.log"; small="$BATS_TEST_TMPDIR/small.log"
  mkbytes "$big" 300
  mkbytes "$small" 40
  run bash "$ROT" "$big" "$small"
  [ "$status" -eq 0 ]
  [ "$(rot_count "$big")" -eq 1 ]       # big rotated
  [ "$(rot_count "$small")" -eq 0 ]     # small untouched
  [ "$(wc -c < "$small" | tr -d ' ')" -eq 40 ]
  grep -q '"rotated":1' "$CC_IDL"
  grep -q '"skipped":1' "$CC_IDL"
}

# ── idempotent: a second run on the now-empty file is a no-op ──
@test "second run after rotation is a no-op" {
  mkbytes "$T" 250
  run bash "$ROT" "$T"; [ "$status" -eq 0 ]
  [ "$(rot_count "$T")" -eq 1 ]
  run bash "$ROT" "$T"                  # T is now 0 bytes → under threshold
  [ "$status" -eq 0 ]
  [ "$(rot_count "$T")" -eq 1 ]         # still just the one rotation
}

# ── ROTATE_TARGETS env override drives the target list ──
@test "ROTATE_TARGETS env override is honored" {
  mkbytes "$T" 250
  ROTATE_TARGETS="$T" run bash "$ROT"   # no positional args
  [ "$status" -eq 0 ]
  [ "$(rot_count "$T")" -eq 1 ]
}
