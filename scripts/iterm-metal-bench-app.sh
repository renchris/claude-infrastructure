#!/bin/bash
# iterm-metal-bench-app.sh — build a launchable, separately-identified iTerm2 clone whose hardcoded
# Metal pane cap is raised, so the all-Metal counterfactual in
# docs/research/terminal-for-30-panes-2026-07-31.md can actually be RUN instead of inferred.
#
# WHY THIS EXISTS. The sharpest falsifiable claim in that doc — "raising iTerm2's 5-pane Metal cap
# would make the freeze WORSE, because the Metal path allocates a CAMetalLayer + CVDisplayLink
# thread + NSTimer PER PANE" — is inferred from disassembly, never measured. Measuring it needs an
# iTerm2 whose cap is raised. It must NOT be the operator's iTerm2: ~19-30 live Claude Code sessions
# run in it, and it must keep its own preferences. Hence a clone with its own CFBundleIdentifier
# (own defaults domain, own LaunchServices identity, runs concurrently with the real one).
#
# 🚨 THE TRAP THIS SCRIPT EXISTS TO ENCODE — measured 2026-07-31, two crash reports.
# A hand-built clone died at launch with "iTermBench cannot be opened because of a problem" and
#     Termination Reason: Namespace DYLD, Code 1 Library missing
#     Library not loaded: @rpath/iTermSwiftPackages.framework/...
#     Reason: ... not valid for use in process: mapping process and mapped file (non-platform)
#             have different Team IDs
# The message names a MISSING LIBRARY, but the framework was present, intact, and the bundle passed
# `codesign --verify --deep --strict` with rc=0. Nothing about the error text points at the actual
# cause, which is why this comment is long.
#
# The cause: iTerm2 ships with the HARDENED RUNTIME (flags=0x10000(runtime)). Editing Info.plist to
# change the bundle id breaks the code seal, so the clone MUST be re-signed. `codesign --sign -`
# ad-hoc PRESERVES the runtime flag while the Developer ID identity is necessarily gone, producing
# adhoc+runtime with NO Team ID. Hardened runtime implies LIBRARY VALIDATION unless the binary
# carries com.apple.security.cs.disable-library-validation. Library Validation admits a non-platform
# library only if it is signed by the SAME Team ID as the loading process — and "no Team ID" never
# satisfies an identity match, not even against another "no Team ID". So AMFI refuses to map the
# app's OWN bundled framework, and dyld reports that refusal as a missing library.
#
# Proven by a three-arm control (all three built from the same bundle, only the signing differs):
#     A  adhoc + runtime, no entitlements                  flags=0x10002  DIED rc=134 (dyld halt)
#     B  adhoc, runtime dropped                            flags=0x2      LAUNCHED
#     C  adhoc + runtime + disable-library-validation      flags=0x10002  LAUNCHED
# Arm A is the negative control and it MUST fail — B and C prove nothing without it.
#
# WE TAKE ARM C, NOT ARM B, AND THE CHOICE IS LOAD-BEARING. B "works" and is one flag simpler, but
# it changes the runtime environment of the process under measurement: hardened runtime governs JIT
# policy, DYLD_* environment acceptance, and library validation itself. This bundle is a MEASURING
# INSTRUMENT whose whole purpose is to be comparable to the shipping iTerm2. Dropping the runtime
# flag would make the bench differ from production on an axis nobody is controlling for. C keeps the
# hardened runtime and relaxes ONLY the one check that ad-hoc signing cannot satisfy.
#
# THE OTHER HALF, and it is the reason a "working" clone can still be worthless: the first clone was
# never actually patched. Its `cmp x8,#0x6` instruction count was IDENTICAL to stock iTerm2 — the
# bundle launched (once signed) but was a plain second iTerm2 with the stock 5-pane cap, and would
# have produced a confident all-Metal measurement of nothing. So the patch here is anchored,
# uniqueness-checked, and RE-VERIFIED by disassembling the patched binary. A bundle that cannot be
# proven patched is deleted, never returned.
#
# USAGE
#   scripts/iterm-metal-bench-app.sh                          # build with cap=64 at the default dir
#   scripts/iterm-metal-bench-app.sh --cap 40 --out /tmp/mb   # explicit cap and build dir
#   scripts/iterm-metal-bench-app.sh --verify-only /tmp/mb/iTermMetalBench.app
#   scripts/iterm-metal-bench-app.sh --no-launch-probe        # build+verify statically, don't launch
#
# TEARDOWN: the clone is a normal app. Quit it from its own UI, or kill the pid this script prints.
# `pkill -x iTermMetalBench` is safe (disjoint from iTerm2, whose accounting name on this box is
# actually '/Applications/iT' — see scripts/terminal-bench.sh). NEVER pkill iTerm2.
set -uo pipefail

SRC_APP="${ITERM_SRC_APP:-/Applications/iTerm.app}"
OUT_DIR="${TMPDIR:-/tmp}/iterm-metal-bench"
CAP=64
LAUNCH_PROBE=1
VERIFY_ONLY=""
BUNDLE_ID="com.googlecode.iterm2.metalbench"
APP_NAME="iTermMetalBench"

die() { echo "iterm-metal-bench-app: $*" >&2; echo "verdict=FAILED"; exit 1; }
note() { echo "  $*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --cap)         CAP="${2:?}"; shift 2 ;;
    --out)         OUT_DIR="${2:?}"; shift 2 ;;
    --src)         SRC_APP="${2:?}"; shift 2 ;;
    --verify-only) VERIFY_ONLY="${2:?}"; shift 2 ;;
    --no-launch-probe) LAUNCH_PROBE=0; shift ;;
    -h|--help)     sed -n '2,60p' "$0"; exit 0 ;;
    *) die "unknown argument '$1'" ;;
  esac
done

command -v python3 >/dev/null 2>&1 || die "python3 is required (Mach-O offset arithmetic)"
command -v codesign >/dev/null 2>&1 || die "codesign is required (Xcode command line tools)"

# ---------------------------------------------------------------------------------------------
# The Mach-O worker. Two jobs, sharing one anchor definition so 'patch' and 'verify' can never
# disagree about what the patch site IS -- a verifier with its own private notion of the target is
# how a patch gets confirmed against something other than what it changed.
#
# THE ANCHOR is deliberately narrow: inside -[PTYTab updateUseMetal] (address from the symbol
# table), the instruction `cmp x8,#<cap>` IMMEDIATELY followed by a `b.hs`. The bare `cmp x8,#6`
# encoding occurs 21 times across this fat binary; the anchored pair occurs once. Requiring exactly
# one match means an iTerm2 update that moves or reshapes this code makes the script REFUSE rather
# than silently patch an unrelated comparison.
# ---------------------------------------------------------------------------------------------
macho_py() {
python3 - "$@" <<'PY'
import struct, subprocess, sys, re

mode, binpath = sys.argv[1], sys.argv[2]
want = int(sys.argv[3])                      # expected current immediate
newimm = int(sys.argv[4]) if len(sys.argv) > 4 else None

ARM64 = 0x0100000C
def slices(d):
    if struct.unpack('>I', d[:4])[0] not in (0xcafebabe, 0xcafebabf):
        return [(ARM64, 0, len(d))]          # thin; assume native
    n = struct.unpack('>I', d[4:8])[0]
    out = []
    for i in range(n):
        o = 8 + i*20
        ct, cs, off, size, al = struct.unpack('>iiIII', d[o:o+20])
        out.append((ct, off, size))
    return out

def text_seg(m):
    ncmds = struct.unpack('<I', m[16:20])[0]
    o = 32
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack('<II', m[o:o+8])
        if cmd == 0x19:
            name = m[o+8:o+24].rstrip(b'\0').decode()
            vmaddr, vmsize, fileoff, filesize = struct.unpack('<QQQQ', m[o+24:o+56])
            if name == '__TEXT':
                return vmaddr, fileoff
        o += cmdsize
    raise SystemExit("no __TEXT segment")

def cmp_x8_enc(imm):
    if not 0 <= imm <= 4095: raise SystemExit("cap out of imm12 range: %d" % imm)
    return 0xF1000000 | (imm << 10) | (8 << 5) | 31

d = bytearray(open(binpath, 'rb').read())
sl = [s for s in slices(bytes(d)) if s[0] == ARM64]
if not sl: raise SystemExit("no arm64 slice in %s" % binpath)
base = sl[0][1]
vmaddr, fileoff = text_seg(bytes(d[base:base+sl[0][2]]))

# Locate the function by symbol, then disassemble ONLY it.
dis = subprocess.run(['otool', '-arch', 'arm64', '-tV', '-p', '-[PTYTab updateUseMetal]', binpath],
                     capture_output=True, text=True).stdout.splitlines()
if len(dis) < 10: raise SystemExit("could not disassemble -[PTYTab updateUseMetal]")

sites = []
prev = None
for line in dis[:600]:
    m = re.match(r'^([0-9a-f]{16})\s+(\S+)\s*(.*)$', line.strip())
    if not m: continue
    addr, mnem, ops = int(m.group(1), 16), m.group(2), m.group(3)
    if prev and prev[1] == 'cmp' and re.match(r'^x8,\s*#0x[0-9a-f]+$', prev[2]) \
       and mnem.startswith('b.hs'):
        imm = int(prev[2].split('#')[1], 16)
        sites.append((prev[0], imm))
    prev = (addr, mnem, ops)

if len(sites) != 1:
    raise SystemExit("ANCHOR NOT UNIQUE: found %d 'cmp x8,#N + b.hs' sites in updateUseMetal "
                     "(expected exactly 1). iTerm2 %s may have reshaped this code; refusing."
                     % (len(sites), binpath))
site_vm, cur = sites[0]
foff = base + (site_vm - vmaddr + fileoff)
onfile = struct.unpack('<I', bytes(d[foff:foff+4]))[0]

if mode == 'verify':
    if cur != want:
        raise SystemExit("cap immediate is %d, expected %d" % (cur, want))
    if onfile != cmp_x8_enc(want):
        raise SystemExit("disassembly and file bytes disagree at %#x" % foff)
    print("ok cap=%d vm=%#x foff=%#x" % (cur, site_vm, foff))
elif mode == 'patch':
    if cur != want:
        raise SystemExit("refusing to patch: current cap is %d, expected stock %d" % (cur, want))
    if onfile != cmp_x8_enc(want):
        raise SystemExit("file bytes %#x do not match expected %#x at %#x"
                         % (onfile, cmp_x8_enc(want), foff))
    struct.pack_into('<I', d, foff, cmp_x8_enc(newimm))
    open(binpath, 'wb').write(bytes(d))
    print("patched cap %d -> %d at foff=%#x" % (want, newimm, foff))
PY
}

# ---------------------------------------------------------------------------------------------
# Sign inside-out. NOT `codesign --deep`: Apple deprecates it for signing, and it applies the SAME
# options to nested code, which is precisely the ambiguity that produced the crash. Every nested
# signable is signed explicitly, deepest first, then the bundle itself.
# ---------------------------------------------------------------------------------------------
sign_bundle() {
  local app="$1" ents="$2" c f
  c="$app/Contents"
  shopt -s nullglob
  for f in "$c"/Frameworks/*.framework "$c"/Frameworks/*.dylib "$c"/XPCServices/*.xpc \
           "$c"/Resources/*.app "$c"/Library/LoginItems/*.app "$c"/MacOS/*; do
    [ -e "$f" ] || continue
    codesign --force --sign - --timestamp=none --options runtime --entitlements "$ents" "$f" \
      >/dev/null 2>&1 || { echo "sign failed: $f" >&2; return 1; }
  done
  shopt -u nullglob
  codesign --force --sign - --timestamp=none --options runtime --entitlements "$ents" "$app" \
    >/dev/null 2>&1 || { echo "sign failed (main bundle): $app" >&2; return 1; }
}

write_entitlements() {
  cat >"$1" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <!-- The one relaxation an ad-hoc re-sign of a hardened-runtime app cannot do without. See the
       header: Library Validation cannot be satisfied by a signature that has no Team ID. -->
  <key>com.apple.security.cs.disable-library-validation</key><true/>
  <!-- Carried over from stock iTerm2's entitlements; the clone renders the same UI. -->
  <key>com.apple.security.cs.allow-jit</key><true/>
  <key>com.apple.security.automation.apple-events</key><true/>
</dict></plist>
PLIST
}

# ---------------------------------------------------------------------------------------------
# VERIFY. Every check that could pass vacuously is written so that it CANNOT: the cap is read back
# out of the patched binary by disassembly, the entitlement is read back out of the signature, and
# the launch verdict comes from the process still being alive -- never from an exit code, because a
# GUI app that lives is killed by us (non-zero) and a GUI app that dies is also non-zero.
# ---------------------------------------------------------------------------------------------
verify_app() {
  local app="$1" rc=0 exe
  exe="$app/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' \
                             "$app/Contents/Info.plist" 2>/dev/null)"
  [ -x "$exe" ] || { echo "  ✗ no executable at $exe"; return 1; }

  local out
  out="$(macho_py verify "$exe" "$CAP" 2>&1)" \
    && note "✓ cap patched and readable: $out" \
    || { echo "  ✗ cap verify: $out"; rc=1; }

  local flags
  flags="$(codesign -dv --verbose=2 "$app" 2>&1 | sed -n 's/.*flags=\([^ ]*\).*/\1/p')"
  case "$flags" in
    *runtime*) note "✓ hardened runtime preserved ($flags)" ;;
    *) echo "  ✗ hardened runtime MISSING ($flags) — bench would not match production"; rc=1 ;;
  esac

  if codesign -d --entitlements - --xml "$app" 2>/dev/null \
       | plutil -convert xml1 -o - - 2>/dev/null \
       | grep -q 'disable-library-validation'; then
    note "✓ disable-library-validation entitlement present"
  else
    echo "  ✗ disable-library-validation entitlement ABSENT — this is the crash, it will not launch"
    rc=1
  fi

  codesign --verify --strict "$app" >/dev/null 2>&1 \
    && note "✓ signature verifies" || { echo "  ✗ signature does not verify"; rc=1; }

  return $rc
}

launch_probe() {
  local app="$1" exe
  exe="$app/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' \
                             "$app/Contents/Info.plist" 2>/dev/null)"
  local home="$OUT_DIR/probe-home"; rm -rf "$home"; mkdir -p "$home"
  local log="$OUT_DIR/probe.log"
  HOME="$home" "$exe" >"$log" 2>&1 &
  local pid=$!
  sleep 6
  if kill -0 "$pid" 2>/dev/null; then
    note "✓ launch probe: process survived dyld (pid $pid) — killing it"
    kill -TERM "$pid" 2>/dev/null; sleep 2; kill -KILL "$pid" 2>/dev/null
    return 0
  fi
  echo "  ✗ launch probe: died at launch — $(head -3 "$log" 2>/dev/null | tr '\n' ' ' | cut -c1-200)"
  return 1
}

# ---------------------------------------------------------------------------------------------
if [ -n "$VERIFY_ONLY" ]; then
  echo "== verify-only  app=$VERIFY_ONLY cap=$CAP"
  if verify_app "$VERIFY_ONLY"; then echo "verdict=OK"; exit 0; else echo "verdict=FAILED"; exit 1; fi
fi

# Refuse to operate on anything but a build directory. The source app is READ-ONLY here; a bug that
# patched /Applications/iTerm.app would break the operator's live terminal hosting ~30 sessions.
case "$OUT_DIR" in
  /Applications/*|/System/*|"$HOME"/Applications/*) die "refusing to build into $OUT_DIR" ;;
esac
[ -d "$SRC_APP" ] || die "source app not found: $SRC_APP"

DEST="$OUT_DIR/$APP_NAME.app"
echo "== iterm-metal-bench-app  src=$SRC_APP cap=$CAP out=$DEST"
mkdir -p "$OUT_DIR" || die "cannot create $OUT_DIR"
rm -rf "$DEST"
cp -R "$SRC_APP" "$DEST" || die "copy failed"
note "copied bundle"

PB=/usr/libexec/PlistBuddy
SRC_EXE_NAME="$($PB -c 'Print :CFBundleExecutable' "$DEST/Contents/Info.plist")"
$PB -c "Set :CFBundleIdentifier $BUNDLE_ID" "$DEST/Contents/Info.plist" \
  || die "could not set CFBundleIdentifier"
$PB -c "Set :CFBundleName $APP_NAME"    "$DEST/Contents/Info.plist" >/dev/null 2>&1
$PB -c "Set :CFBundleExecutable $APP_NAME" "$DEST/Contents/Info.plist" || die "could not set exe name"
mv "$DEST/Contents/MacOS/$SRC_EXE_NAME" "$DEST/Contents/MacOS/$APP_NAME" || die "could not rename exe"
note "identity: $BUNDLE_ID / $APP_NAME (own defaults domain, runs alongside the real iTerm2)"

# Patch BEFORE signing: any byte written after signing invalidates the seal we just made.
out="$(macho_py patch "$DEST/Contents/MacOS/$APP_NAME" 6 "$CAP" 2>&1)" \
  || { rm -rf "$DEST"; die "cap patch: $out"; }
note "$out"

ENTS="$OUT_DIR/bench.entitlements"
write_entitlements "$ENTS"
sign_bundle "$DEST" "$ENTS" || { rm -rf "$DEST"; die "signing failed"; }
note "signed inside-out (adhoc + runtime + disable-library-validation)"

echo "-- verifying"
if ! verify_app "$DEST"; then rm -rf "$DEST"; die "verification failed — bundle deleted, not returned"; fi

if [ "$LAUNCH_PROBE" = 1 ]; then
  echo "-- launch probe"
  if ! launch_probe "$DEST"; then rm -rf "$DEST"; die "launch probe failed — bundle deleted"; fi
fi

echo "app=$DEST"
echo "cap=$CAP"
echo "verdict=OK"
