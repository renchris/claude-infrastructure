#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# cc-authstore-probe.sh <claude-binary> — is the vendor credential-WRITE-LOSS window still open?
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# Answers ONE question about a CANDIDATE Claude Code binary, by reading the binary — never a claim,
# never a remembered verdict:
#
#   When the macOS keychain write times out, does Claude Code still (a) skip its own plaintext
#   fallback and (b) report the credential as saved anyway?
#
# WHY THIS EXISTS.  `docs/research/forced-relogin-rootcause-2026-08-02.md` UPDATE 3 filed this as
# "known-open, filed rather than fixed": it is upstream and we cannot close it. A known-open upstream
# defect that lives only in prose has no way to learn it changed — so the day Anthropic fixes it we
# would keep paying for compensating machinery, and the day they make it WORSE we would not notice.
# This probe is the sensor. `docs/research/vendor-report-cc-authstore-write-loss.md` is the report.
#
# THE FOUR VERDICTS (exit code == verdict; stdout == JSON evidence):
#   0  FIXED       the transient-skip branch is GONE. News: re-read the vendor report, and close
#                  backlog 4adbeab56aa7 — our compensations may be retirable.
#   1  STATUS-QUO  still present, exactly as measured on the 2.1.220 baseline. NOT an upgrade
#                  blocker: a candidate that matches the binary we already run is not a regression.
#   2  WORSE       the keychain writer is there but the PLAINTEXT FALLBACK IS GONE — the only
#                  safety net under a failed keychain write was removed. A real regression.
#   3  UNREADABLE  none of the anchors resolve. The credential-storage layer was restructured, or
#                  the bundle stopped being introspectable. Fail-closed ON PURPOSE: every auth-health
#                  compensation we run (verify-by-effect heal, fingerprinted rejection records, the
#                  rotation-concurrency gate) rests on assumptions about this layer. The remedy is to
#                  re-derive the anchors below against the new bundle — not to wave it through.
#
# The anchors are TELEMETRY SLUGS and SHELL-COMMAND LITERALS, never minified identifiers: slugs
# survive a re-minify, `Q5i`/`bFc`/`_Qt` do not. Identifiers ARE used, but only resolved dynamically
# (find the name at the use-site, then look up its definition), so a rename cannot silently blind us.
#
# Usage:
#   scripts/cc-authstore-probe.sh ~/.claude-220/node_modules/.bin/claude
#   scripts/cc-authstore-probe.sh "$(command -v claude)"        # resolves wrappers/symlinks
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail

BASELINE_VERSION="2.1.220"      # the version every axis below was measured on, by hand, 2026-08-08
BASELINE_TIMEOUT_MS=2000        # security(1) subprocess timeout
BASELINE_ARGV_CHARS=4032        # over this, the hex credential blob moves from stdin onto argv

usage() { sed -n '2,45p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 64; }

[ $# -ge 1 ] || usage
case "$1" in -h|--help|help) usage ;; esac

BIN="$1"

# ---- resolve to the file that actually carries the bundle -------------------------------------------
# node_modules/.bin/claude is a symlink to bin/claude.exe; a package DIR is accepted for convenience.
if [ -d "$BIN" ]; then
  for cand in "$BIN/bin/claude.exe" "$BIN/cli.js" "$BIN/node_modules/@anthropic-ai/claude-code/bin/claude.exe"; do
    [ -f "$cand" ] && { BIN="$cand"; break; }
  done
fi
# readlink -f is GNU-only on some boxes; python3 is already a hard dependency of the gate.
RESOLVED="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$BIN" 2>/dev/null || printf '%s' "$BIN")"

if [ ! -f "$RESOLVED" ]; then
  printf '{"binary":"%s","verdict":"UNREADABLE","reason":"not a file"}\n' "$RESOLVED"
  exit 3
fi

command -v python3 >/dev/null 2>&1 || { echo "✗ python3 required" >&2; exit 64; }

# ---- candidate version, from the package manifest beside the binary ---------------------------------
# Read, never EXECUTED: a probe that runs the candidate to ask its version has already given an
# unvetted binary a turn. Absent manifest ⇒ null, which is evidence, not an error.
CAND_VERSION=""
for pj in "$(dirname "$RESOLVED")/../package.json" "$(dirname "$RESOLVED")/package.json"; do
  [ -f "$pj" ] || continue
  CAND_VERSION="$(python3 -c 'import json,sys
try: print(json.load(open(sys.argv[1])).get("version") or "")
except Exception: print("")' "$pj" 2>/dev/null)"
  [ -n "$CAND_VERSION" ] && break
done

python3 - "$RESOLVED" "$BASELINE_VERSION" "$BASELINE_TIMEOUT_MS" "$BASELINE_ARGV_CHARS" "$CAND_VERSION" <<'PY'
import json, mmap, re, sys

path, baseline_version = sys.argv[1], sys.argv[2]
baseline_timeout, baseline_argv = int(sys.argv[3]), int(sys.argv[4])
version = sys.argv[5] or None

# ── anchors ────────────────────────────────────────────────────────────────────────────────────────
# Each is a string the vendor emits for a REASON (a metric name, a literal argv), so it survives
# re-minification. Keyed on the mechanism, not on this build's spelling of it.
A_WRITER   = b'add-generic-password -U -a "${'   # the keychain write, as a template literal
A_SKIP     = b'primary_transient_skip_fallback'  # the branch that returns BEFORE trying plaintext
A_FALLBACK = b'plaintext_fallback_used'          # the branch that proves a fallback exists at all
A_PLAINSTORE = b'name:"plaintext"'               # the plaintext store object itself
A_BOTHFAIL = b'primary_and_fallback_failed'      # both-failed arm — present iff the composite is intact
A_METRIC   = b'secure_storage_credentials_write' # the metric the three arms above report under

with open(path, "rb") as fh:
    try:
        mm = mmap.mmap(fh.fileno(), 0, access=mmap.ACCESS_READ)
    except ValueError:          # zero-length file
        print(json.dumps({"binary": path, "verdict": "UNREADABLE",
                          "reason": "empty file", "baseline": baseline_version}))
        sys.exit(3)

    def has(needle): return mm.find(needle) != -1

    writer      = has(A_WRITER)
    skip        = has(A_SKIP)
    fallback    = has(A_FALLBACK) and has(A_PLAINSTORE)
    both_fail   = has(A_BOTHFAIL)
    metric      = has(A_METRIC)

    # ── the two constants, resolved through the USE-SITE so a rename cannot blind us ───────────────
    # At the write we expect (verbatim, 2.1.220):
    #   i=`add-generic-password -U -a "${r}" -s "${t}" -X "${o}"\n`,s;
    #   if(i.length<=Lcg) s=await ax("security",["-i"],{...,timeout:_Qt});
    # so: find the template, take a window, read the identifier off each use, then look up `<id>=<n>`.
    timeout_ms = argv_chars = None
    timeout_keyed_on_timedout = None
    at = mm.find(A_WRITER)
    if at != -1:
        window = mm[at:at + 1400]
        m = re.search(rb'timeout:([A-Za-z_$][A-Za-z0-9_$]*)', window)
        if m:
            d = re.search(rb'\b' + re.escape(m.group(1)) + rb'=(\d+)\b', mm)
            if d:
                timeout_ms = int(d.group(1))
        m = re.search(rb'\.length<=([A-Za-z_$][A-Za-z0-9_$]*)\)', window)
        if m:
            d = re.search(rb'\b' + re.escape(m.group(1)) + rb'=(\d+)\b', mm)
            if d:
                argv_chars = int(d.group(1))
        # is the "transient" classification still keyed on the subprocess TIMING OUT?
        timeout_keyed_on_timedout = bool(
            re.search(rb'transient:[A-Za-z_$][A-Za-z0-9_$]*\.timedOut', window))

# ── verdict ────────────────────────────────────────────────────────────────────────────────────────
# Order matters: UNREADABLE is judged first (nothing else is meaningful without anchors), then the
# safety-net regression, then the defect itself.
if not (writer or skip or fallback or metric):
    verdict, reason = "UNREADABLE", (
        "none of the credential-store anchors resolve — the storage layer was restructured or the "
        "bundle is no longer introspectable; re-derive the anchors in scripts/cc-authstore-probe.sh")
elif writer and not fallback:
    verdict, reason = "WORSE", (
        "the keychain writer is present but the plaintext FALLBACK is gone — a failed keychain "
        "write now has no safety net at all")
elif skip:
    verdict, reason = "STATUS-QUO", (
        "the transient-skip branch is still present: a timed-out keychain write still returns "
        "before the plaintext fallback — unchanged from the %s baseline" % baseline_version)
else:
    verdict, reason = "FIXED", (
        "the transient-skip branch is GONE — a failed keychain write can now reach the plaintext "
        "fallback; re-read docs/research/vendor-report-cc-authstore-write-loss.md")

report = {
    "probe": "cc-authstore-probe",
    "binary": path,
    "version": version,
    "baseline": {"version": baseline_version,
                 "write_timeout_ms": baseline_timeout,
                 "argv_threshold_chars": baseline_argv},
    "axes": {
        "keychain_writer":     "present" if writer else "absent",
        "transient_skip":      "present" if skip else "absent",
        "plaintext_fallback":  "present" if fallback else "absent",
        "both_failed_arm":     "present" if both_fail else "absent",
        "write_metric":        "present" if metric else "absent",
        "write_timeout_ms":    timeout_ms,
        "argv_threshold_chars": argv_chars,
        "transient_keyed_on_timeout": timeout_keyed_on_timedout,
    },
    "verdict": verdict,
    "reason": reason,
}
print(json.dumps(report, indent=2))
sys.exit({"FIXED": 0, "STATUS-QUO": 1, "WORSE": 2, "UNREADABLE": 3}[verdict])
PY
