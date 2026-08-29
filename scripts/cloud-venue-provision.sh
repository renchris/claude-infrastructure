#!/usr/bin/env bash
# cloud-venue-provision.sh — make a cloud VM's OWN land path able to render a verdict.
#
#   scripts/cloud-venue-provision.sh            check, install what is missing, re-verify, verdict
#   scripts/cloud-venue-provision.sh --check    read-only: the census and the verdict, install nothing
#   scripts/cloud-venue-provision.sh --selftest prove the verdict function discriminates (no box needed)
#
# WHY THIS EXISTS. docs/plans/BACKLOG_DRAIN_24_7.md's 2026-08-29 addendum ends "Not fixable as code
# from here. A SessionStart hook would mean editing .claude/settings.json, which the dispatch rails
# forbid in place. It is a venue-provisioning step and is recorded as one." The first sentence is
# true of a HOOK and not of a SCRIPT: a dispatched session can run one command before it works, and
# that costs no settings edit, no hook registration and no launchd change. This file is that command.
#
# WHAT IT IS NOT. It does not weaken a gate, widen an allowlist, edit settings.json, or touch a ref.
# It installs two tools the land gate needs in order to SPEAK, and then asserts they made the gate
# speak. Everything else about the land is unchanged.
#
# ── THE CORRECTION THIS FILE CARRIES, AND IT IS THE REASON THE TWO TOOLS ARE NOT INTERCHANGEABLE ──
# The addendum calls shellcheck and bats "Both locks … provisionable in the venue" and prescribes one
# `apt-get install -y shellcheck bats`. The prescription is right and the framing is wrong: MEASURED
# on a cloud VM 2026-08-29 (Ubuntu, shellcheck 0.9.0, bats 1.10.0, HEAD == origin/main), only ONE of
# them is a lock, and the other fails in the opposite direction — silently.
#
#   [the checker] ABSENT → scripts/bats-shellcheck-lint.sh exits 2 (--selftest AND bare) →
#                       ship-land.sh:3444 routes 2 to bats_sc_nonverdict → GATE_KILLED → exit 9.
#                       A HARD LOCK. Measured: `--precheck --working` rc 9, stderr "the usual cause
#                       is that shellcheck is not installed on this host".
#                       (Spelled "[the checker]" on purpose: a comment line BEGINNING with the
#                       checker's own name parses as a directive, SC1072/SC1073, and aborts the lint
#                       for this whole file — ship-land.sh:2552 names the same trap, and this file
#                       tripped it on its first run.)
#   bats ABSENT       → NOT a lock at all. gate_bats runs a bare `bats "$@"` (ship-land.sh:1749),
#                       which exits 127 with ZERO `not ok`; run_scoped_suite's discriminator is the
#                       TAP BODY and never the exit code, so 127 reads as a CUT, the exoneration
#                       re-run is a second cut, and it returns 2. run_smoke maps that to cut=1 →
#                       SMOKE_STATE="partial" → `return 0`, and the land PROCEEDS.
#
# The polarity is not a bug in ship-land.sh, and this file does not change it. "A non-verdict never
# blocks a land; the post-land verifier decides" (ship-land.sh:2136) is a sound trade ON THE BOX THAT
# HAS A POST-LAND VERIFIER. A cloud VM does not: the verifier is a launchd job on the operator's Mac,
# and the same plan records it INERT for days (backlog 01ab05685857). So on THIS venue "partial"
# means no process anywhere will ever execute the diff — the silent skip that fe6540a6 went blocking
# to eliminate for shellcheck, still live in the smoke arm and invisible because it exits 0.
#
# Hence the two tools have different jobs and both are required:
#   the checker lets the land HAPPEN.       bats lets the land MEAN something.
# A venue that installs only shellcheck lands green-looking commits that nothing ever ran.
#
# ── AND A THIRD LOCK THE PRESCRIPTION ITSELF WALKS INTO: PRESENCE IS NOT A VERSION ────────────────
# `apt-get install -y shellcheck` gives **0.9.0** from the Ubuntu archive. `run_gate`'s statics arm
# runs a BARE `shellcheck "${sc_todo[@]}"` (ship-land.sh:2586) over every CHANGED shell file IN FULL
# and reds on ANY non-zero. Measured here on `origin/main`'s own UNMODIFIED `scripts/ship-land.sh`:
#
#     v0.9.0  · LC_ALL unset (this container's default) → rc 2, output CRASHES mid-stream
#                                       ("commitBuffer: invalid argument"), 48 of the findings printed
#     v0.9.0  · LC_ALL=C.UTF-8                          → rc 1, 114 findings (SC2317 noise)
#     v0.11.0 · any locale                             → rc 0, ZERO findings
#
# So the prescribed command installs a checker that REDs unmodified trunk, and it does so twice over:
# 0.9.0's SC2317 fires on shapes 0.11 does not flag, and the repo's `.shellcheckrc` waives exactly
# SC2001 and SC2015 by name (deliberately — "a lowered severity threshold would have waived every
# future info/style finding sight-unseen"). That file's own header says it was verified against
# **0.11**, which is the version this repo is written for. The rc-2 crash is the second, sharper
# half: a Haskell runtime writing this repo's em-dashes and arrows under a non-UTF-8 locale dies,
# and the statics arm cannot tell rc 2 from rc 1 — a NON-VERDICT read as a red, which is the exact
# conflation `bats_sc_nonverdict` exists to prevent one arm over.
#
# ⚠ Indentation does NOT save a comment from the directive parser: the three rows above began
# `#     <tool name> 0.9.0…` and SC1073 fired on them, which is the FOURTH instance of this same trap
# in one diff. Only the first WORD matters, whatever precedes it.
#
# The version floor subsumes the locale: 0.11 is clean at the inherited locale. This file therefore
# probes the checker by RUNNING it on a witness that trunk keeps clean, never by parsing --version
# alone — a version string is a claim about the binary, the witness is a claim about this box.
set -uo pipefail
# CAPTURED BEFORE THE FORCED PREPEND, AND IT IS LOAD-BEARING. The line below is the launchd-safe
# idiom every sibling here uses, and it puts /usr/bin AHEAD of everything — including /usr/local/bin,
# where an upstream binary is installed. So this process resolves a tool differently from the shell
# that will run the land, and a verdict taken under the forced PATH can certify a checker the LAND
# will never see. The upgrade arm verifies against THIS value, not against ours.
AMBIENT_PATH="${PATH}"
# APPENDED, NOT PREPENDED — and this file is the one place in the repo where that difference is a
# CORRECTNESS bug rather than a style choice. The sibling launchd-safe idiom puts the standard dirs
# FIRST, which is right for a script that must survive an empty PATH and does not care WHICH copy of
# a tool it gets. This script's entire job is to answer "which copy will the LAND get", so a forced
# /usr/bin:… prefix makes it measure the distro binary even after an upstream one is installed ahead
# of it — reporting STALE-CHECKER forever on a venue that is actually fine, and re-fetching on every
# run. Caught by tests/cloud-venue-provision.bats, which went red on the positive control the moment
# the upgrade arm landed. Appending keeps the empty-PATH guarantee and leaves ambient precedence — the
# land's precedence — intact.
export PATH="${PATH}:/usr/bin:/bin:/usr/sbin:/sbin"

# RESOLVED THROUGH $0's SYMLINKS FIRST, then derived — the canonical form, copied from the sibling
# lints rather than re-invented. `~/.claude/{scripts,hooks,bin}/` are per-FILE symlinks into the
# checkout, so a bare `dirname "$0"/..` on the live path yields `~/.claude`, which has no tests/ and
# no scripts/ship-land.sh to use as a witness. This script would then read NOT-APPLICABLE — a clean
# verdict about the wrong tree, on the only path that matters. Caught by self-path-lint, which
# refused the first spelling; no `readlink -f`, which is GNU-only and this repo's box is BSD.
SELF="$0"
while [ -L "$SELF" ]; do
  _link="$(readlink "$SELF")"
  case "$_link" in
    /*) SELF="$_link" ;;
    *)  SELF="$(dirname "$SELF")/$_link" ;;
  esac
done
REPO_ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
SC_LINT="${CC_VENUE_SC_LINT:-$REPO_ROOT/scripts/bats-shellcheck-lint.sh}"

# ── the verdict function, pure, so --selftest can drive every cell with no box at all ─────────────
# $1 = the checker's state: absent | stale | ok   $2 = bats present? (1|0)
# $3 = does this repo have tests/*.bats? (1|0) — the .bats ratchet's entry condition is a property of
#      the REPO, not of the diff (ship-land.sh:3421), so a repo with no suites is not locked by a
#      missing shellcheck and must not be reported as if it were.
# $4 = is a post-land verifier reachable on this box? (1|0) — what makes "partial" survivable.
# Echoes "<TOKEN>\t<one line>". TOKEN ∈ LOCKED | STALE-CHECKER | UNGATED | READY | NOT-APPLICABLE | UNKNOWN.
#
# THE ORDER IS THE ORDER THE LAND MEETS THEM, and that is what makes it right rather than arbitrary:
# LOCKED outranks STALE-CHECKER outranks UNGATED. A land that cannot start cannot be ungated, and a
# land the statics arm reds never reaches the smoke — so naming a softer failure first would send a
# reader to fix the thing that changes nothing yet.
venue_verdict() {
  local sc="$1" bt="$2" suites="$3" verifier="$4"
  if [ "$suites" != 1 ]; then
    if [ "$bt" = 1 ]; then
      printf 'NOT-APPLICABLE\tThis repo has no tests/*.bats, so the .bats shellcheck ratchet never fires and there is no smoke to run. Nothing to provision.\n'
    else
      printf 'NOT-APPLICABLE\tThis repo has no tests/*.bats: the ratchet never fires. bats is still absent, so any suite added later would land unrun.\n'
    fi
    return 0
  fi
  if [ "$sc" = absent ]; then
    printf 'LOCKED\tThe checker is absent: bats-shellcheck-lint exits 2, ship-land routes that to GATE_KILLED, and EVERY land here exits 9 — docs-only included, because the arm keys on the repo having tests/*.bats, not on the diff.\n'
    return 0
  fi
  if [ "$sc" = stale ]; then
    printf 'STALE-CHECKER\tThe checker is present but does NOT render a clean verdict on a witness file trunk keeps clean, so ship-land'"'"'s statics arm (a bare run over every changed shell file, red on ANY non-zero) will red this land on findings the diff never wrote. Ubuntu ships 0.9.0; this repo is written for 0.11 and its .shellcheckrc waives two codes BY NAME, not by severity.\n'
    return 0
  fi
  if [ "$bt" != 1 ]; then
    if [ "$verifier" = 1 ]; then
      printf 'UNGATED\tbats is absent: every selected suite exits 127 with zero TAP not-ok lines, the smoke attests "partial" and the land PROCEEDS unrun. A post-land verifier is reachable here, so it is the remaining net — but nothing executed the diff at land time.\n'
    else
      printf 'UNGATED\tbats is absent: every selected suite exits 127 with zero TAP not-ok lines, the smoke attests "partial" and the land PROCEEDS unrun. There is NO post-land verifier on this box, so no process anywhere will ever execute this diff. This exits 0 and is therefore silent.\n'
    fi
    return 0
  fi
  if [ "$sc" != ok ]; then
    # FAIL CLOSED ON AN OPERAND WE DO NOT RECOGNISE. The checker's state is a WORD, not a flag, so a
    # typo or a future third failure mode would otherwise fall straight through to READY and certify
    # a box nobody measured. Caught by the selftest cell added with this arm, not by review.
    printf 'UNKNOWN\tThe checker state "%s" is not one this verdict knows (absent|stale|ok), so there is NO verdict about this venue — not a clean one.\n' "$sc"
    return 0
  fi
  printf 'READY\tThe checker renders a clean verdict on the witness and bats is present: the land gate can reach a verdict and the smoke can earn one.\n'
}

# A DOCUMENTED TEST SEAM, AND IT IS ONE-DIRECTIONAL BY CONSTRUCTION: CC_VENUE_ABSENT can only make
# a tool look ABSENT, never present. It exists because this file forces /usr/bin onto PATH two lines
# below (the sibling launchd-safe idiom), which makes PATH-shielding useless as a way to drive the
# absent cells from a suite. A seam that could manufacture PRESENCE would let a test prove READY on
# a box that cannot land — the one direction that must never be reachable — so this one is wired to
# produce only the pessimistic answer, and tests/cloud-venue-provision.bats pins that asymmetry.
have() {
  case " ${CC_VENUE_ABSENT:-} " in *" $1 "*) return 1 ;; esac
  command -v "$1" >/dev/null 2>&1
}
b()    { if "$@" >/dev/null 2>&1; then echo 1; else echo 0; fi; }

# The verifier probe is deliberately conservative and one-sided. It answers "is a post-land verifier
# plausibly reachable", never "is one running": launchd is macOS-only and this file's whole point is
# that it runs off-box, so a false 1 here would soften the UNGATED line on exactly the venue that
# must not have it softened. Absence of the platform ⇒ 0, which is the safe direction.
verifier_present() {
  [ "$(uname -s)" = "Darwin" ] && have launchctl && return 0
  return 1
}

repo_has_suites() {
  [ -d "$REPO_ROOT/tests" ] && ls "$REPO_ROOT"/tests/*.bats >/dev/null 2>&1
}

# THE WITNESS, AND WHY IT IS A RUN AND NOT A VERSION STRING. `--version` is a claim about the binary;
# what the gate cares about is whether a bare run over a long-lived repo script exits 0 on THIS box,
# which folds in the version, the locale, and any .shellcheckrc that is or is not being found. The
# witness is scripts/ship-land.sh itself, deliberately: it is the file the statics arm most often has
# to clear, the gate requires it clean anyway, and trunk keeps it that way — so a non-zero here is
# never news about the witness and always news about the venue. A DIFFERENT witness is a different
# experiment, hence CC_VENUE_WITNESS is named rather than globbed.
# Resolved INSIDE the probe, not once at file scope: a caller (the selftest, a suite) that sets
# CC_VENUE_WITNESS for one call must actually get that witness, and a file-scope capture silently
# ignores it — which is a control that measures a different question than its subject.

# → absent | stale | ok. The `stale` arm pools "wrong version" with "wrong locale" ON PURPOSE: both
# make the same bare run non-zero, the cure for both is the same newer binary (0.11 is clean at the
# inherited locale where 0.9.0 crashes), and a token per cause would be a distinction the reader
# cannot act on differently.
checker_state() {
  local witness="${CC_VENUE_WITNESS:-$REPO_ROOT/scripts/ship-land.sh}"
  have shellcheck || { echo absent; return 0; }
  [ -f "$witness" ] || { echo ok; return 0; }   # no witness ⇒ no evidence ⇒ never invent a failure
  if shellcheck "$witness" >/dev/null 2>&1; then echo ok; else echo stale; fi
}

census() {   # prints the three reads, then the verdict line; sets VERDICT_TOKEN
  local sc bt su vf line
  # Called in the plain `if` form rather than through the b() indirection: a static analyser cannot
  # see a function reached only via "$@", and reports it as dead code (SC2329). Silencing that with
  # a disable directive would trade a true statement about reachability for a comment nobody reruns.
  sc="$(checker_state)"; bt="$(b have bats)"
  if repo_has_suites;   then su=1; else su=0; fi
  if verifier_present;  then vf=1; else vf=0; fi
  echo "host   : $(uname -s) $(uname -m) · repo $REPO_ROOT"
  printf 'locale : LANG=%s LC_ALL=%s LC_CTYPE=%s\n' \
    "${LANG:-<unset>}" "${LC_ALL:-<unset>}" "${LC_CTYPE:-<unset>}"
  printf 'tools  : shellcheck %s (witness %s) · bats %s\n' \
    "$( [ "$sc" != absent ] && shellcheck --version 2>/dev/null | sed -n 's/^version: /v/p' | head -1 || echo ABSENT )" \
    "$sc" \
    "$( [ "$bt" = 1 ] && bats --version 2>/dev/null | head -1 || echo ABSENT )"
  printf 'repo   : tests/*.bats %s · post-land verifier %s\n' \
    "$( [ "$su" = 1 ] && echo present || echo absent )" \
    "$( [ "$vf" = 1 ] && echo reachable || echo 'NOT on this box' )"
  line="$(venue_verdict "$sc" "$bt" "$su" "$vf")"
  VERDICT_TOKEN="${line%%$'\t'*}"
  printf 'verdict: %s — %s\n' "$VERDICT_TOKEN" "${line#*$'\t'}"
}

# ── --selftest ────────────────────────────────────────────────────────────────────────────────────
if [ "${1:-}" = "--selftest" ]; then
  fails=0; checks=0
  expect() { checks=$((checks+1)); [ "$2" = "$1" ] || { fails=$((fails+1)); printf 'SELFTEST FAIL: %s (want %s, got %s)\n' "$3" "$1" "$2"; }; }
  tok() { venue_verdict "$1" "$2" "$3" "$4" | cut -f1; }
  # 1-3. each failure reaches its OWN token, and they are three different tokens — a verdict that
  #      collapsed "cannot run" into "ran vacuously" is the exact error this file was written to fix.
  expect LOCKED         "$(tok absent 1 1 0)" 'a missing checker did not read LOCKED'
  expect STALE-CHECKER  "$(tok stale  1 1 0)" 'a checker that reds the witness did not read STALE-CHECKER'
  expect UNGATED        "$(tok ok     0 1 0)" 'a missing bats did not read UNGATED'
  # 4-5. PRECEDENCE, in the order the land meets them: absent outranks stale outranks ungated. Each
  #      is asserted against the token it must beat, so a reordering cannot pass by luck.
  expect LOCKED         "$(tok absent 0 1 0)" 'absent+no-bats did not give precedence to the hard lock'
  expect STALE-CHECKER  "$(tok stale  0 1 0)" 'stale+no-bats did not give precedence to the statics arm'
  # 6. the positive control — with everything good the token is none of the failures, so 1-5 mean
  #    something. Without it a verdict stuck on any single failure token passes every cell above.
  expect READY          "$(tok ok 1 1 0)" 'a good venue did not read READY'
  # 7-8. the ratchet keys on the REPO having suites, so a repo without them is not convicted by a
  #      checker problem at all. Without this arm the script would convict every consumer repo.
  expect NOT-APPLICABLE "$(tok absent 1 0 0)" 'a repo with no .bats suites was reported LOCKED'
  expect NOT-APPLICABLE "$(tok stale  0 0 0)" 'a repo with no .bats suites was reported STALE-CHECKER'
  # 9. …and NOT-APPLICABLE still distinguishes bats present from absent in its TEXT, because the
  #    next suite added to such a repo would land unrun. Token equal, sentence not.
  expect 1 "$( [ "$(venue_verdict ok 0 0 0)" != "$(venue_verdict ok 1 0 0)" ] && echo 1 || echo 0 )" \
           'NOT-APPLICABLE said the same thing with and without bats'
  # 10-11. the verifier operand moves only the UNGATED sentence, and never the token. It is the whole
  #      reason this venue is different from the operator's box, so it must be visible and must not
  #      be able to turn a failure into a pass.
  expect UNGATED "$(tok ok 0 1 1)" 'a reachable verifier changed the UNGATED token'
  expect 1 "$( [ "$(venue_verdict ok 0 1 1)" != "$(venue_verdict ok 0 1 0)" ] && echo 1 || echo 0 )" \
           'the verifier operand did not change the UNGATED sentence'
  # 12. READY is insensitive to the verifier — nothing about a green smoke depends on it.
  expect 1 "$( [ "$(venue_verdict ok 1 1 1)" = "$(venue_verdict ok 1 1 0)" ] && echo 1 || echo 0 )" \
           'READY was made to depend on the verifier'
  # 13. every token is reachable and distinct: a stuck verdict passes 1-12 only if it also passes this.
  expect 5 "$(printf '%s\n' "$(tok absent 1 1 0)" "$(tok stale 1 1 0)" "$(tok ok 0 1 0)" "$(tok ok 1 1 0)" "$(tok ok 1 0 0)" | sort -u | wc -l | tr -d ' ')" \
           'the five tokens are not five distinct strings'
  # 14. an UNRECOGNISED checker state must not silently read as good. The operand is a word now, and
  #     a typo that fell through to READY would certify a box nobody measured.
  expect 1 "$( [ "$(tok wat 1 1 0)" != READY ] && echo 1 || echo 0 )" 'an unknown checker state fell through to READY'
  # 15. the probe is one-sided by construction: off-Darwin it must answer 0, because a false
  #      "verifier reachable" softens the one line that must stay hard on a cloud VM.
  if [ "$(uname -s)" != "Darwin" ]; then
    expect 0 "$(b verifier_present)" 'verifier_present answered 1 on a non-Darwin host'
  else
    checks=$((checks+1))
  fi
  # 16. the witness probe is a RUN, not a version string, and it must abstain rather than convict
  #     when there is no witness to run on — "no evidence" is never "bad".
  expect ok "$(CC_VENUE_WITNESS=/nonexistent/witness checker_state)" 'an absent witness manufactured a failure'
  if [ "$fails" = 0 ]; then
    echo "cloud-venue-provision --selftest: $checks/$checks — LOCKED on an absent checker, STALE-CHECKER on one that reds a witness trunk keeps clean, UNGATED on a missing bats: three distinct failures, ordered as the land meets them and each asserted against the token it must beat; READY as the positive control; a repo with no .bats suites abstains as NOT-APPLICABLE in both directions yet still says which tool is missing; an unrecognised checker state cannot reach READY; the verifier operand moves the UNGATED sentence and never any token; all five tokens distinct; the verifier probe answers 0 off-Darwin; and the witness probe abstains when there is no witness."
    exit 0
  fi
  echo "cloud-venue-provision --selftest: FAILED ($fails of $checks)."
  exit 1
fi

# The version this repo is written for. NOT a guess: .shellcheckrc's own header records that its
# `disable=` policy was verified against 0.11, and 0.11.0 measured rc 0 / zero findings on trunk's
# scripts/ship-land.sh where 0.9.0 measured rc 1 with 114.
SC_WANT="${CC_VENUE_SHELLCHECK_VERSION:-0.11.0}"
UPGRADE=1

MODE=provision
for a in "$@"; do
  case "$a" in
    provision|--provision) MODE=provision ;;
    --check)               MODE=check ;;
    --no-upgrade)          UPGRADE=0 ;;
    -h|--help)             sed -n '2,6p' "$0"; exit 0 ;;
    *) echo "cloud-venue-provision: unknown argument '$a' (expected --check, --no-upgrade, --selftest, or nothing)." >&2; exit 2 ;;
  esac
done

VERDICT_TOKEN=""
echo "cloud-venue-provision — plan docs/plans/BACKLOG_DRAIN_24_7.md, addendum 2026-08-29"
census

[ "$MODE" = check ] && { case "$VERDICT_TOKEN" in READY|NOT-APPLICABLE) exit 0 ;; *) exit 1 ;; esac; }

if [ "$VERDICT_TOKEN" = READY ] || [ "$VERDICT_TOKEN" = NOT-APPLICABLE ]; then
  echo "nothing to provision."
elif [ "$VERDICT_TOKEN" = UNKNOWN ]; then
  echo "⛔ no verdict about this venue — refusing to act on a state this script does not model." >&2
  exit 3
else
  # ── arm 1: the packages, from the distro. Deliberately not clever: one package manager, the two
  # packages the addendum names, and a REFUSAL rather than a sudo prompt where it cannot run
  # unattended — a dispatched session has nobody to answer a prompt, so a prompt is a hang.
  # AN ARRAY, not a space-joined string: an unquoted expansion is how a package list becomes a glob,
  # and this one is interpolated into a privileged command. The joined form survives only in the
  # human-facing messages, where it is quoted.
  want=()
  have shellcheck || want+=(shellcheck)
  have bats       || want+=(bats)
  if [ "${#want[@]}" -gt 0 ]; then
    want_s="${want[*]}"
    if ! have apt-get; then
      echo "⛔ apt-get is absent — cannot provision from here. Install ${want_s} by this venue's own means and re-run." >&2
      exit 3
    fi
    if [ "$(id -u)" != 0 ]; then
      echo "⛔ not root and this must not prompt (a dispatched session has nobody to answer). Run: sudo apt-get install -y ${want_s}" >&2
      exit 3
    fi
    echo "→ installing: ${want_s}"
    apt-get install -y "${want[@]}" >/dev/null 2>&1 || { echo "⛔ apt-get install failed for: ${want_s}" >&2; exit 3; }
  fi

  # ── arm 2: the VERSION, which the distro cannot supply. This is the arm the addendum's one-line
  # prescription does not have, and without it a provisioned VM reds unmodified trunk. Ubuntu's
  # newest shellcheck is 0.9.0; this repo is written for 0.11 (its own .shellcheckrc says so) and
  # the statics arm reds on ANY non-zero from a bare run. So when the witness still fails after the
  # package install, fetch the upstream release.
  #
  # THIS IS A NETWORK FETCH OF A BINARY, AND IT IS NAMED AS ONE RATHER THAN BURIED. It is the
  # project's own GitHub release — the same trust class as the distro archive, not better — and the
  # sha256 of what was fetched is PRINTED, so a reader can compare it against the release page
  # instead of taking this script's word. It is not an authenticity check and does not pretend to be.
  # `--no-upgrade` skips this arm entirely and leaves STALE-CHECKER standing, for a venue whose
  # policy is that binaries come from the archive or not at all.
  if [ "$(checker_state)" = stale ] && [ "$UPGRADE" = 1 ]; then
    echo "→ the distro's checker still reds the witness — fetching shellcheck v${SC_WANT} from upstream"
    tgz="$(mktemp -d)/sc.tar.xz"
    url="https://github.com/koalaman/shellcheck/releases/download/v${SC_WANT}/shellcheck-v${SC_WANT}.linux.$(uname -m).tar.xz"
    if ! curl -fsSL --max-time 180 -o "$tgz" "$url"; then
      echo "⛔ could not fetch ${url} — leaving the distro checker in place; the verdict below stands." >&2
    else
      printf '  fetched %s\n  sha256  %s  (compare against the release page; this is provenance, not proof)\n' \
        "$url" "$(sha256sum "$tgz" | cut -d' ' -f1)"
      tar -xJf "$tgz" -C "$(dirname "$tgz")" 2>/dev/null
      newsc="$(dirname "$tgz")/shellcheck-v${SC_WANT}/shellcheck"
      if [ -x "$newsc" ]; then
        install -m 0755 "$newsc" /usr/local/bin/shellcheck 2>/dev/null \
          || cp "$newsc" /usr/local/bin/shellcheck
        # /usr/local/bin must WIN over the distro copy, and this file forces /usr/bin to the FRONT
        # of PATH near the top. Prepending here rather than editing that line keeps the launchd-safe
        # base intact and makes the precedence local and visible.
        PATH="/usr/local/bin:$PATH"; export PATH
        hash -r 2>/dev/null || true
        # …AND THE LAND DOES NOT RUN UNDER OUR PATH. Verify against the AMBIENT one: if a shell that
        # never sourced this script would still resolve the distro copy, our READY would be a claim
        # about a binary the gate never invokes — the one direction this file must not fail in. On
        # that venue, replace the distro copy in place so BOTH resolutions agree, and say so.
        if [ "$(PATH="$AMBIENT_PATH" command -v shellcheck 2>/dev/null)" != /usr/local/bin/shellcheck ]; then
          echo "  note: this venue's PATH resolves /usr/bin before /usr/local/bin — replacing the distro copy so the LAND sees the same binary this check does."
          install -m 0755 "$newsc" /usr/bin/shellcheck 2>/dev/null || cp "$newsc" /usr/bin/shellcheck
          hash -r 2>/dev/null || true
        fi
      else
        echo "⛔ the fetched archive did not contain an executable at the expected path — nothing installed." >&2
      fi
    fi
  fi

  echo "→ re-reading the venue:"
  census
fi

# ── the assertion arm: presence is not a verdict, so make each tool SPEAK before claiming ready ───
# A tool on PATH that cannot answer is the same non-verdict one that is absent, and this is the arm
# that separates them. `--selftest` is the lint's OWN discrimination proof, so a green one is the
# strongest available statement that its clean verdict will mean something at land time.
rc=0
if [ -x "$SC_LINT" ] && repo_has_suites; then
  if out="$("$SC_LINT" --selftest 2>&1)"; then
    printf 'assert : bats-shellcheck-lint --selftest OK — %s\n' "$(printf '%s' "$out" | sed -n 's/^bats-shellcheck-lint --selftest: \([0-9]*\/[0-9]*\).*/\1/p' | head -1)"
  else
    printf 'assert : bats-shellcheck-lint --selftest did NOT pass (exit %s) — the land will not reach a verdict here.\n' "$?" >&2
    rc=1
  fi
fi
if have bats; then
  printf 'assert : bats runs — %s\n' "$(bats --version 2>&1 | head -1)"
elif repo_has_suites; then
  echo "assert : bats still absent — the smoke will attest \"partial\" and the land will proceed UNRUN." >&2
  rc=1
fi

[ "$rc" = 0 ] && echo "✓ venue ready: this box's land path can both run and mean something."
exit "$rc"
