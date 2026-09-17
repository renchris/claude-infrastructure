#!/usr/bin/env bats
# kitty-crash-attribute — ATTRIBUTING A STRIPPED CPython EXTENSION CRASH.
#
# WHY THIS SUITE EXISTS. cc-backlog bf6af099a712 closed its own investigation with
# "attribution needs a symbol-bearing build or a sandbox reproduction", because `nm` on the
# shipped kitty.fast_data_types.so yields only undefined imports. That treated the SYMBOL TABLE
# as the only name source. Two other tables survive stripping — LC_FUNCTION_STARTS (bounds) and
# the module's PyMethodDef arrays (name next to address, because CPython must read them at
# import) — and their intersection names the function with no repro and no rebuild.
#
# WHAT THESE CASES ARE FOR. Two of them pin GUARDS, not output, and both guard a way the tool
# can produce a CONFIDENT WRONG ANSWER rather than an error:
#   * a build whose UUID does not match the report (offsets do not transfer between builds —
#     the tool's first draft attributed two sandbox crashes against the shipped map);
#   * a pc of 0, which a naive bisect maps to the first function in the image.
# Both are silent in the direction that reads as success, which is why they are pinned here
# rather than left to the happy path.
#
# HERMETICITY. The fixtures are REDACTED copies (faulting thread, 6 frames, no environment) so
# the suite does not depend on ~/Library/Logs/DiagnosticReports, which rotates. The shipped
# kitty binary is a genuine external dependency: every case that needs it SKIPS when the UUID
# on disk is not the one the fixture was taken against, so a kitty upgrade retires the case
# instead of reddening it.

setup() {
  # FIXTURE $HOME, but capture the real one FIRST. The subject never writes anything, yet an
  # unfixtured suite is one edit away from touching the operator's live ~/ and the land gate
  # rightly refuses to run bats at all while one exists. The positive control genuinely needs a
  # symbol-bearing build that lives under the real home, so that ONE read-only path uses
  # REAL_HOME explicitly — naively fixturing $HOME would make the control silently skip, which
  # is a vacuous control, not a hermetic one.
  REAL_HOME="$HOME"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  TOOL="$REPO/scripts/kitty-crash-attribute.py"
  FIX="$REPO/tests/fixtures"
  SO="/Applications/kitty.app/Contents/Resources/Python/lib/kitty-extensions/kitty.fast_data_types.so"
  # The UUID the fixtures were captured against. A kitty upgrade changes it; see HERMETICITY.
  WANT_UUID="ca7c2fb0-544e-35b7-bf30-93235293adb1"
  TMP="$BATS_TEST_TMPDIR"
}

have_subject() {
  [ -x "$TOOL" ] || return 1
  [ -r "$SO" ] || return 1
  command -v dyld_info >/dev/null 2>&1 || return 1
  grep -qi "$WANT_UUID" <(dwarfdump --uuid "$SO" 2>/dev/null) || return 1
  return 0
}

@test "the tool exists and is executable" {
  [ -x "$TOOL" ]
}

@test "the tool parses as python3" {
  run python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$TOOL"
  [ "$status" -eq 0 ] || false
}

@test "20:13:49 crash attributes to viewport_for_window" {
  have_subject || skip "shipped kitty 0.48.2 (uuid $WANT_UUID) not present"
  run "$TOOL" "$FIX/kitty-crash-201349.ips"
  [ "$status" -eq 0 ] || false
  # THE load-bearing assertion: the item said this was unattributable.
  [[ "$output" == *"viewport_for_window"* ]] || false
}

@test "the fault site is self-verified against the fault address" {
  have_subject || skip "shipped kitty 0.48.2 not present"
  run "$TOOL" "$FIX/kitty-crash-201349.ips"
  # An attribution that merely NAMES a function is a claim; decoding the faulting
  # instruction and finding it dereferences exactly 0x20 is what makes it a measurement.
  [[ "$output" == *"ldp dereferences +0x20"* ]] || false
  [[ "$output" == *"VERIFIED:"* ]] || false
}

@test "13:58 crash attributes its python entry point to update_pointer_shape" {
  have_subject || skip "shipped kitty 0.48.2 not present"
  run "$TOOL" "$FIX/kitty-crash-135806.ips"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"update_pointer_shape"* ]] || false
}

@test "GUARD: a uuid mismatch REFUSES instead of emitting a wrong name" {
  have_subject || skip "shipped kitty 0.48.2 not present"
  # Same report, same on-disk binary, ONE variable changed: the uuid the report claims.
  # Offsets do not transfer between builds, so the only correct behaviour is refusal.
  python3 - "$FIX/kitty-crash-201349.ips" "$TMP/wrong-uuid.ips" <<'PY'
import json, sys
raw = open(sys.argv[1]).read()
i = raw.index("\n")
hdr, body = raw[:i], json.loads(raw[i:])
for im in body["usedImages"]:
    if "fast_data_types" in (im.get("name") or ""):
        im["uuid"] = "deadbeef-0000-0000-0000-000000000000"
open(sys.argv[2], "w").write(hdr + "\n" + json.dumps(body))
PY
  run "$TOOL" "$TMP/wrong-uuid.ips"
  [ "$status" -eq 3 ] || false
  [[ "$output" == *"REFUSED"* ]] || false
  # and it must NOT have guessed a name off the mismatched build
  [[ "$output" != *"viewport_for_window"* ]] || false
}

@test "GUARD: a pc of 0 is UNATTRIBUTABLE, not the first function in the image" {
  have_subject || skip "shipped kitty 0.48.2 not present"
  python3 - "$FIX/kitty-crash-201349.ips" "$TMP/nullpc.ips" <<'PY'
import json, sys
raw = open(sys.argv[1]).read()
i = raw.index("\n")
hdr, body = raw[:i], json.loads(raw[i:])
body["threads"][0]["frames"][0]["imageOffset"] = 0
open(sys.argv[2], "w").write(hdr + "\n" + json.dumps(body))
PY
  run "$TOOL" "$TMP/nullpc.ips"
  [[ "$output" == *"UNATTRIBUTABLE"* ]] || false
  [[ "$output" != *"viewport_for_window"* ]] || false
}

@test "POSITIVE CONTROL: recovered addresses are real functions in a symbolized build" {
  have_subject || skip "shipped kitty 0.48.2 not present"
  CTL="$REAL_HOME/k482/kitty/fast_data_types.so"
  [ -r "$CTL" ] || skip "no symbol-bearing 0.48.2 build at $CTL"
  # The whole method rests on "a PyMethodDef ml_meth is a function entry address". This is the
  # arm that can refute that: on a build where nm works, every address the method table yields
  # must BE a text symbol. Without this the suite only shows the tool is self-consistent.
  run "$TOOL" --control "$SO" --against "$CTL"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"control: PASS"* ]] || false
}
