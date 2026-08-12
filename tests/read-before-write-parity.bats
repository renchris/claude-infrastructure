#!/usr/bin/env bats
# read-before-write-parity.sh — the shim that restores Claude Code's native read-before-write refusal
# on accounts where a server-side GrowthBook flag has switched it off.
#
# WHY THIS SUITE EXISTS (2026-08-12). The shim had existed as an UNTRACKED file in the shared checkout
# since 2026-08-05 — never committed, never on origin/main, referenced by zero settings.json, one
# `git clean -f -d` from gone. It could not be landed without coverage, because it is a hook that
# INTERCEPTS Write/Edit: a bug in it is worse than its absence. A shim that refuses too much stops
# real work; a shim that refuses nothing is theatre. This suite pins both directions.
#
# THE PREMISE, RE-MEASURED RATHER THAN INHERITED. Two prior sources disagreed about the flag and BOTH
# were stale. Measured 2026-08-12 across all four account config dirs, `tengu_velvet_mallet_<bucket>`
# is TRUE in 16 of 16 (account × bucket) cells — the rollout completed — so the native guard is off
# everywhere this fleet runs. Confirmed live, not merely from the cache: a Bash-created file that the
# session never Read was overwritten by `Write` and the tool returned success, with only the advisory
# `backup-before-write.sh` firing. The shim is therefore load-bearing on every account, which raises
# the cost of getting it wrong and is the reason for the mutation controls at the bottom.
#
# THE ASYMMETRY IS THE POINT, so it is pinned in BOTH directions:
#   · a file the session never touched must be REFUSED          (R1 — the whole purpose)
#   · a file the session DID read must still be ALLOWED         (R2 — the positive control; without
#     it, a shim that refuses unconditionally would pass every R1 test)
#   · every uncertainty must land on ALLOW                      (fail-open: the shim mirrors the
#     binary's own `Ke(name,!1)` default, so where it cannot tell, the native guard is still on)
#
# R1 and R2 are deliberately built from ONE fixture differing in ONE record — the Read of the target.
# Any pair that differed in more than that could pass for the wrong reason.
#
# RED-PROOF. Every load-bearing assertion is proved by MUTATION: a copy of the real shim is deranged
# at the exact line the assertion depends on, and the test asserts the verdict inverts. A control that
# cannot fail proves nothing (MEMORY.md control-must-replay-the-real-artifact). Each mutant is checked
# to have actually applied (`cmp`) and to still be valid bash (`bash -n`), so a mutation that silently
# no-ops or breaks the parse cannot masquerade as a passing control.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/hooks/lib/read-before-write-parity.sh"
  [ -f "$LIB" ] || { echo "missing $LIB"; return 1; }
  # HERMETIC, and this one matters more than usual. The subject resolves its flag cache from
  # $CLAUDE_CONFIG_DIR, falling back to $HOME/.claude — i.e. the operator's LIVE account config.
  # Both seams are fixtured before any body runs, so no case can read the real ~/.claude, and a
  # fixture typo cannot write to it either.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$CLAUDE_CONFIG_DIR"
  W="$BATS_TEST_TMPDIR/w"; mkdir -p "$W"
  EMPTYPATH="$BATS_TEST_TMPDIR/emptypath"; mkdir -p "$EMPTYPATH"
  TARGET="$W/target.txt"
  printf 'original content\n' > "$TARGET"
}

# A flag cache holding exactly the key=value pairs in $@ (e.g. tengu_velvet_mallet_opus_5=true).
cfg() {
  python3 - "$CLAUDE_CONFIG_DIR/.claude.json" "$@" <<'PY'
import json, sys
feats = {}
for kv in sys.argv[2:]:
    k, v = kv.split("=", 1)
    feats[k] = {"true": True, "false": False}.get(v, v)
json.dump({"cachedGrowthBookFeatures": feats}, open(sys.argv[1], "w"))
PY
}

# A transcript whose assistant records carry $2 as the model ("NONE" ⇒ omit the field entirely),
# plus one tool_use per "Tool:path" spec in $3.. — no specs ⇒ a transcript with no tool_use at all.
tx() {
  local out="$1"; shift
  python3 - "$out" "$@" <<'PY'
import json, sys
out, model = sys.argv[1], sys.argv[2]
def msg(content):
    m = {"content": content}
    if model != "NONE":
        m["model"] = model
    return {"type": "assistant", "message": m}
rows = [{"type": "user", "message": {"content": "go"}}]
for spec in sys.argv[3:]:
    tool, path = spec.split(":", 1)
    rows.append(msg([{"type": "tool_use", "name": tool, "input": {"file_path": path}}]))
rows.append(msg([{"type": "text", "text": "done"}]))
open(out, "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
PY
  printf '%s' "$out"
}

# rc of the contract, sourced fresh each time (the lib is pure — safe to re-source).
#   rc 0 = DENY the write · rc 1 = allow it
deny_rc() {
  bash -c '. "$0"; rbw_should_deny "$1" "$2" "$3" >/dev/null 2>&1; echo $?' \
    "$LIB" "${1:-}" "${2:-}" "${3:-}"
}
# Same, against a deranged copy at $1.
deny_rc_lib() {
  bash -c '. "$0"; rbw_should_deny "$1" "$2" "$3" >/dev/null 2>&1; echo $?' \
    "$1" "${2:-}" "${3:-}" "${4:-}"
}
gd_rc() { bash -c '. "$0"; rbw_guard_disabled "$1" >/dev/null 2>&1; echo $?' "$LIB" "${1:-}"; }
bucket_of() { bash -c '. "$0"; rbw_bucket "$1"' "$LIB" "${1:-}"; }

# A mutant of the real shim with every line containing the fixed string $1 deleted.
# Deletion (not substitution) is used throughout so no sed metacharacter escaping can silently fail
# to apply — a mutation that does not apply is a control that cannot fail.
mutant() { # $1=fixed string to delete, $2=out
  grep -vF "$1" "$LIB" > "$2"
  ! cmp -s "$LIB" "$2" || { echo "mutation '$1' did not apply — control is vacuous"; false; }
  bash -n "$2" || { echo "mutation '$1' produced invalid bash — it would red for the wrong reason"; false; }
}

# ── R1 / R2: THE CONTRACT, pinned as a matched pair ───────────────────────────────────────────────

@test "R1 DENY: guard off + file exists + session never touched it ⇒ refuse (rc 0)" {
  # THE load-bearing assertion. This is the native refusal the flag took away, restored.
  cfg tengu_velvet_mallet_opus_5=true
  local t; t="$(tx "$W/tx.jsonl" claude-opus-5 "Read:$W/unrelated.txt")"
  [ "$(deny_rc "$t" "$TARGET" "$W")" -eq 0 ] || false
}

@test "R2 POSITIVE CONTROL: the SAME write, after a Read of that exact file ⇒ allow (rc 1)" {
  # Differs from R1 by exactly one transcript record. Without this, a shim hardcoded to `return 0`
  # would pass R1 and every other deny test in this file while blocking all legitimate work.
  cfg tengu_velvet_mallet_opus_5=true
  local t; t="$(tx "$W/tx.jsonl" claude-opus-5 "Read:$W/unrelated.txt" "Read:$TARGET")"
  [ "$(deny_rc "$t" "$TARGET" "$W")" -eq 1 ] || false
}

@test "R2: a prior Write of the file also counts as touched ⇒ allow" {
  cfg tengu_velvet_mallet_opus_5=true
  local t; t="$(tx "$W/tx.jsonl" claude-opus-5 "Write:$TARGET")"
  [ "$(deny_rc "$t" "$TARGET" "$W")" -eq 1 ] || false
}

@test "R2: a prior Edit of the file also counts as touched ⇒ allow" {
  cfg tengu_velvet_mallet_opus_5=true
  local t; t="$(tx "$W/tx.jsonl" claude-opus-5 "Edit:$TARGET")"
  [ "$(deny_rc "$t" "$TARGET" "$W")" -eq 1 ] || false
}

@test "R1 is per-FILE, not per-session: reading one file does not license writing another" {
  # The bug that would make R2 pass vacuously — treating "this session read something" as consent.
  cfg tengu_velvet_mallet_opus_5=true
  printf 'other\n' > "$W/other.txt"
  local t; t="$(tx "$W/tx.jsonl" claude-opus-5 "Read:$W/other.txt")"
  [ "$(deny_rc "$t" "$TARGET" "$W")" -eq 0 ] || false
}

# ── THE FLAG GATE: this hook may only act where the binary has stopped acting ─────────────────────

@test "flag FALSE ⇒ allow — the native guard is still refusing; stay out" {
  cfg tengu_velvet_mallet_opus_5=false
  local t; t="$(tx "$W/tx.jsonl" claude-opus-5 "Read:$W/unrelated.txt")"
  [ "$(deny_rc "$t" "$TARGET" "$W")" -eq 1 ] || false
}

@test "flag ABSENT for THIS bucket ⇒ allow, even when a SIBLING bucket is true" {
  # Pins that the lookup is bucket-specific. A shim that tested "any velvet_mallet key is true"
  # would deny on an account where only some other model's guard had been lifted.
  cfg tengu_velvet_mallet_opus_4_8=true tengu_velvet_mallet_sonnet_4_6=true
  local t; t="$(tx "$W/tx.jsonl" claude-opus-5 "Read:$W/unrelated.txt")"
  [ "$(deny_rc "$t" "$TARGET" "$W")" -eq 1 ] || false
}

@test "a MISSING flag cache ⇒ allow (a miss is not an absence of the guard)" {
  rm -f "$CLAUDE_CONFIG_DIR/.claude.json"
  local t; t="$(tx "$W/tx.jsonl" claude-opus-5 "Read:$W/unrelated.txt")"
  [ "$(deny_rc "$t" "$TARGET" "$W")" -eq 1 ] || false
}

@test "an UNPARSEABLE flag cache ⇒ allow, never a deny on a failed read" {
  printf 'this is not json\n' > "$CLAUDE_CONFIG_DIR/.claude.json"
  local t; t="$(tx "$W/tx.jsonl" claude-opus-5 "Read:$W/unrelated.txt")"
  [ "$(deny_rc "$t" "$TARGET" "$W")" -eq 1 ] || false
}

@test "rbw_guard_disabled: TRUE ⇒ rc 0, and that is the only rc 0" {
  # The unit positive control. Every allow-direction test above would also pass against a predicate
  # wired to `return 1` unconditionally; this is what excludes that.
  cfg tengu_velvet_mallet_opus_5=true
  [ "$(gd_rc claude-opus-5)" -eq 0 ] || false
  [ "$(gd_rc claude-opus-4-8)" -eq 1 ] || false
  [ "$(gd_rc "")" -eq 1 ] || false
}

@test "rbw_guard_disabled: no jq on PATH ⇒ rc 1 (cannot tell ⇒ the binary is still guarding)" {
  cfg tengu_velvet_mallet_opus_5=true
  # `/bin/bash` by absolute path: with PATH emptied, `env` cannot look up the interpreter itself and
  # the run exits 127 — which would pass a `-ne 0` assertion while testing nothing at all.
  run env "PATH=$EMPTYPATH" /bin/bash -c '. "$0"; rbw_guard_disabled claude-opus-5' "$LIB"
  [ "$status" -eq 1 ]
}

# ── EVERY OTHER UNCERTAINTY ALSO LANDS ON ALLOW ──────────────────────────────────────────────────

@test "a CREATE (target does not exist) ⇒ allow — never guarded, natively or here" {
  cfg tengu_velvet_mallet_opus_5=true
  local t; t="$(tx "$W/tx.jsonl" claude-opus-5 "Read:$W/unrelated.txt")"
  [ "$(deny_rc "$t" "$W/brand-new.txt" "$W")" -eq 1 ] || false
}

@test "an empty target path ⇒ allow" {
  cfg tengu_velvet_mallet_opus_5=true
  local t; t="$(tx "$W/tx.jsonl" claude-opus-5 "Read:$W/unrelated.txt")"
  [ "$(deny_rc "$t" "" "$W")" -eq 1 ] || false
}

@test "no model on any assistant record ⇒ allow (the first-tool-call gap, named in the header)" {
  cfg tengu_velvet_mallet_opus_5=true
  local t; t="$(tx "$W/tx.jsonl" NONE "Read:$W/unrelated.txt")"
  [ "$(deny_rc "$t" "$TARGET" "$W")" -eq 1 ] || false
}

@test "an unknown model whose bucket is in no cache ⇒ allow" {
  cfg tengu_velvet_mallet_opus_5=true
  local t; t="$(tx "$W/tx.jsonl" claude-nextgen-9 "Read:$W/unrelated.txt")"
  [ "$(deny_rc "$t" "$TARGET" "$W")" -eq 1 ] || false
}

@test "a MISSING transcript ⇒ allow" {
  cfg tengu_velvet_mallet_opus_5=true
  [ "$(deny_rc "$W/nope.jsonl" "$TARGET" "$W")" -eq 1 ] || false
}

@test "a transcript with NO file-touching tool_use ⇒ allow (the post-compaction residue)" {
  # readFileState survives a compaction that rewrites the transcript, so a Read can exist in the
  # binary's memory and nowhere on disk. Treating "no records" as "never read" would deny a
  # legitimate write after every compaction — the one residue that fails toward refusal if missed.
  cfg tengu_velvet_mallet_opus_5=true
  local t; t="$(tx "$W/tx.jsonl" claude-opus-5)"
  [ "$(deny_rc "$t" "$TARGET" "$W")" -eq 1 ] || false
}

@test "an UNPARSEABLE transcript line ⇒ allow, never a partial answer read as 'never touched'" {
  # jq skips the bad record but still exits non-zero, so the read is discarded as cannot-tell. A
  # partial parse could omit the very Read that licenses the write — the false-deny direction.
  cfg tengu_velvet_mallet_opus_5=true
  local t; t="$(tx "$W/tx.jsonl" claude-opus-5 "Read:$TARGET")"
  printf 'this is not json\n' >> "$t"
  [ "$(deny_rc "$t" "$TARGET" "$W")" -eq 1 ] || false
}

# ── CANONICALISATION: two spellings of one file must not read as two files ────────────────────────

@test "a SYMLINKED spelling of the read still licenses the write ⇒ allow" {
  # The false-deny direction, and the normal case here rather than an edge one: /tmp is a symlink to
  # /private/tmp on macOS and this repo's live layer is symlinks into the checkout. Uncanonicalised,
  # the oracle would report "never touched" for a file the session had just read.
  cfg tengu_velvet_mallet_opus_5=true
  ln -s "$W" "$BATS_TEST_TMPDIR/link"
  local t; t="$(tx "$W/tx.jsonl" claude-opus-5 "Read:$BATS_TEST_TMPDIR/link/target.txt")"
  [ "$(deny_rc "$t" "$TARGET" "$W")" -eq 1 ] || false
}

@test "a RELATIVE target resolves against cwd and matches the absolute read ⇒ allow" {
  cfg tengu_velvet_mallet_opus_5=true
  local t; t="$(tx "$W/tx.jsonl" claude-opus-5 "Read:$TARGET")"
  [ "$(deny_rc "$t" "target.txt" "$W")" -eq 1 ] || false
}

@test "a path containing a space is matched, not split" {
  cfg tengu_velvet_mallet_opus_5=true
  printf 'x\n' > "$W/my file.txt"
  local t; t="$(tx "$W/tx.jsonl" claude-opus-5 "Read:$W/my file.txt")"
  [ "$(deny_rc "$t" "$W/my file.txt" "$W")" -eq 1 ] || false
}

# ── BUCKET DERIVATION: mirrors the binary's bQt(), including two steps that were missing ──────────
# Read out of 2.1.220's claude.exe on 2026-08-12:
#   bQt(e){ let t=e.replace(/\[1m\]$/i,"").replace(/^claude-/,"").replaceAll("-","_");
#           return /^[a-z0-9_]{1,40}$/.test(t) ? xp(t) : Te("nonconforming") }

@test "bucket: the ordinary model ids map as the binary maps them" {
  [ "$(bucket_of claude-opus-5)" = "opus_5" ] || false
  [ "$(bucket_of claude-opus-4-8)" = "opus_4_8" ] || false
  [ "$(bucket_of claude-sonnet-4-6)" = "sonnet_4_6" ] || false
}

@test "bucket: the 1M-context variant strips to its PARENT bucket" {
  # The gap this suite's subject had until 2026-08-12: without the strip this built `opus_5[1m]`,
  # missed the cache key and allowed — so the shim was blind on exactly the variant whose parent
  # bucket is TRUE. Fail-open, therefore silent; only reading bQt could find it.
  [ "$(bucket_of "claude-opus-5[1m]")" = "opus_5" ] || false
  [ "$(bucket_of "claude-opus-5[1M]")" = "opus_5" ] || false
}

@test "bucket: a nonconforming id yields the LITERAL 'nonconforming', not a coerced key" {
  # The binary's failure branch is a fixed string, and `tengu_velvet_mallet_nonconforming` is absent
  # from every cache (measured 2026-08-12) ⇒ allow. Coercing `.` to `_` instead could land on a REAL
  # key and deny where the binary allows — a divergence in the dangerous direction.
  [ "$(bucket_of "claude-opus-4.8")" = "nonconforming" ] || false
  [ "$(bucket_of "claude-OPUS-5")" = "nonconforming" ] || false
  [ "$(bucket_of "")" = "nonconforming" ] || false
}

@test "END-TO-END: a session on the 1M-context variant is guarded like its parent (rc 0)" {
  # The contract-level consequence of the strip. Pre-fix this returned 1 (allow) — see the mutation
  # control below, which replays that exact behaviour.
  cfg tengu_velvet_mallet_opus_5=true
  local t; t="$(tx "$W/tx.jsonl" "claude-opus-5[1m]" "Read:$W/unrelated.txt")"
  [ "$(deny_rc "$t" "$TARGET" "$W")" -eq 0 ] || false
}

# ── MUTATION CONTROLS — prove each assertion above can actually FAIL ──────────────────────────────

@test "mutation: dropping the flag check denies where the native guard is still ON" {
  # Without the flag gate this hook would add refusals the binary never had, on every account.
  local bad="$BATS_TEST_TMPDIR/m-flag.sh"
  mutant '[ "$val" = "true" ] || return 1' "$bad"
  cfg tengu_velvet_mallet_opus_5=false
  local t; t="$(tx "$W/tx.jsonl" claude-opus-5 "Read:$W/unrelated.txt")"
  [ "$(deny_rc "$t" "$TARGET" "$W")" -eq 1 ] || false
  [ "$(deny_rc_lib "$bad" "$t" "$TARGET" "$W")" -eq 0 ] || false
}

@test "mutation: dropping the touched-path match refuses a file the session JUST read" {
  # The sabotage that makes R2 vacuous — a shim that denies everything.
  local bad="$BATS_TEST_TMPDIR/m-match.sh"
  mutant '= "$tc" ] && return 1' "$bad"
  cfg tengu_velvet_mallet_opus_5=true
  local t; t="$(tx "$W/tx.jsonl" claude-opus-5 "Read:$TARGET")"
  [ "$(deny_rc "$t" "$TARGET" "$W")" -eq 1 ] || false
  [ "$(deny_rc_lib "$bad" "$t" "$TARGET" "$W")" -eq 0 ] || false
}

@test "mutation: dropping the existence check refuses a CREATE" {
  local bad="$BATS_TEST_TMPDIR/m-exist.sh"
  mutant '[ -f "$target" ] || return 1' "$bad"
  cfg tengu_velvet_mallet_opus_5=true
  local t; t="$(tx "$W/tx.jsonl" claude-opus-5 "Read:$W/unrelated.txt")"
  [ "$(deny_rc "$t" "$W/brand-new.txt" "$W")" -eq 1 ] || false
  [ "$(deny_rc_lib "$bad" "$t" "$W/brand-new.txt" "$W")" -eq 0 ] || false
}

@test "mutation: treating a cannot-tell transcript as 'no reads' denies every write in the session" {
  # The worst available failure: one unreadable transcript and the hook refuses all work until the
  # session ends. This is why the rc-2 arm is separate from the rc-1 arm.
  local bad="$BATS_TEST_TMPDIR/m-rc.sh"
  mutant '[ "$rc" -eq 0 ] || return 1' "$bad"
  cfg tengu_velvet_mallet_opus_5=true
  local t; t="$(tx "$W/tx.jsonl" claude-opus-5 "Read:$TARGET")"
  printf 'this is not json\n' >> "$t"
  [ "$(deny_rc "$t" "$TARGET" "$W")" -eq 1 ] || false
  [ "$(deny_rc_lib "$bad" "$t" "$TARGET" "$W")" -eq 0 ] || false
}

@test "mutation: the RANGE form of the conformance class accepts an id the binary rejects" {
  # Replays the defect this suite caught on 2026-08-12: written `[!a-z0-9_]`, the glob bracket is
  # resolved by the locale's COLLATION rather than by ASCII, so `OPUS_5` passed as conforming. The
  # substitution is pure alphanumerics — no metacharacter can fail to apply and leave a vacuous pass.
  local bad="$BATS_TEST_TMPDIR/m-range.sh"
  sed 's/abcdefghijklmnopqrstuvwxyz0123456789_/a-z0-9_/' "$LIB" > "$bad"
  ! cmp -s "$LIB" "$bad" || { echo "mutation did not apply — control is vacuous"; false; }
  bash -n "$bad" || { echo "mutation produced invalid bash"; false; }
  [ "$(bucket_of "claude-OPUS-5")" = "nonconforming" ] || false
  # ABSTAIN rather than assert if this environment's collation does NOT interleave case: the mutant
  # would then be inert and a green here would be evidence of nothing.
  local ranged; ranged="$(bash -c '. "$0"; rbw_bucket "$1"' "$bad" "claude-OPUS-5")"
  if [ "$ranged" = "nonconforming" ]; then
    skip "this locale's collation rejects uppercase in a-z — the mutant is inert, no verdict"
  fi
  [ "$ranged" = "OPUS_5" ] || false
}

@test "mutation: removing the 1M strip replays the pre-fix blindness on that variant" {
  # Byte-for-byte the behaviour this file's subject shipped with until 2026-08-12, so the end-to-end
  # test above is proved to discriminate rather than to pass on the fixture's shape.
  local bad="$BATS_TEST_TMPDIR/m-1m.sh"
  mutant 'm="${m%\[1m\]}"' "$bad"
  cfg tengu_velvet_mallet_opus_5=true
  local t; t="$(tx "$W/tx.jsonl" "claude-opus-5[1m]" "Read:$W/unrelated.txt")"
  [ "$(deny_rc "$t" "$TARGET" "$W")" -eq 0 ] || false
  [ "$(deny_rc_lib "$bad" "$t" "$TARGET" "$W")" -eq 1 ] || false
}
