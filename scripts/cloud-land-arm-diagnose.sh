#!/usr/bin/env bash
# cloud-land-arm-diagnose.sh — the ONE read that settles why the cloud return/land arm stops.
#
#   scripts/cloud-land-arm-diagnose.sh            print the reads and a verdict
#   scripts/cloud-land-arm-diagnose.sh --selftest  prove the verdict function discriminates
#
# WHY THIS EXISTS. Backlog f85fce7c26f5 has been dispatched four times and every dispatch reached the
# same wall: the numbers are derivable from `origin` by any cloud VM, and the MECHANISM is not. It
# needs three reads that exist only on the operator's box — the launchd job's environment, what
# `/bin/zsh -lc` exports there, and the sweep's own IDL journal — and each dispatch ended by writing
# those three commands into a document for a human to run by hand. Four documents, zero runs. This
# file is that hand-work made executable, so the residue is ONE command instead of a worksheet.
#
# READ-ONLY, BY CONSTRUCTION. It runs `launchctl print` (a dump), one `zsh -lc echo`, and reads two
# files. It writes nothing, takes no lock, touches no ref, and spends no quota — so it is safe to run
# on a live box mid-sweep, which is the only time some of these answers are interesting.
#
# THE HYPOTHESIS IT TESTS. `scripts/autonomy-sweep.sh` gates both cloud rails on an EXACT compare:
#
#     _cc_cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; _cc_cfg="${_cc_cfg%/}"
#     [ "$0" = "$_cc_cfg/scripts/autonomy-sweep.sh" ] && _cloudret_deployed=1
#
# The two operands come from different places. `$0` is fixed by the plist, which hardcodes
# `~/.claude/scripts/autonomy-sweep.sh` (launchd/com.chrisren.autonomy-sweep.plist:10). `_cc_cfg`
# comes from CLAUDE_CONFIG_DIR, which three migrations in this repo record the operator's shell
# exporting as `~/.claude-next` (migrations/0013…:26, 0009…:80, 0006…:87), one of them noting it may
# be exported UNEXPANDED. Let them disagree and the gate refuses its own caller: cloud-return and
# cloud-refusal-route file `skipped-*` on every 300 s tick, forever.
#
# `zsh -lc` is non-interactive: it sources .zshenv/.zprofile/.zlogin and NOT .zshrc. So an export at
# ~/.zshrc alone would NOT do it, which is exactly why this is measured here rather than asserted.
# The evidence for the arm stopping at all, and the four instruments behind it, is
# docs/research/cloud-land-arm-step-2026-08-25.md §6.
#
# WHAT A CLEAN RUN DOES NOT PROVE. `cloud_return_rc: 0` says the PASS ran, never that anything
# landed — per-session outcomes live in the return ledger, and §D below reads it for that reason.
set -uo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH}"

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; CFG="${CFG%/}"
IDL="${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
CLOUD_DIR="${CC_CLOUD_STATE:-$HOME/.claude/autonomy/cloud}"
ERRLOG="${CC_SWEEP_ERRLOG:-$HOME/.claude/logs/autonomy-sweep.err.log}"
PLIST_SPELLING="${HOME%/}/.claude/scripts/autonomy-sweep.sh"
LABEL="com.chrisren.autonomy-sweep"

hr() { printf '%s\n' "────────────────────────────────────────────────────────────────────────────"; }

# ── the verdict function, factored out so --selftest can drive it with no box at all ─────────────
# $1 = the CLAUDE_CONFIG_DIR a login shell exports ("" = unset)   $2 = $HOME
# $3 = the newest cloud_return_rc seen in the IDL ("" = the journal is readable and holds no such
#      row; the literal "__unreadable__" = the journal could not be read at all)
# Echoes "<TOKEN>\t<one line>". TOKEN ∈ DIVERGENCE | NOT-DEPLOYED | RUNNING | NO-ROWS | UNREADABLE
# | UNKNOWN. UNREADABLE outranks everything below the compare: a sensor that could not run is not a
# verdict, and "no rows" would be a claim this script has no evidence for (the repo's own law, and
# the one an off-box run of this file would otherwise break — it reads NO-ROWS on every Linux VM).
verdict() {
  local cfg="$1" home="$2" rc="$3" want deployed
  home="${home%/}"; cfg="${cfg%/}"
  want="$home/.claude"
  [ -n "$cfg" ] || cfg="$want"
  if [ "$cfg" != "$want" ]; then
    printf 'DIVERGENCE\tCLAUDE_CONFIG_DIR is %s but the plist invokes %s/scripts/autonomy-sweep.sh — the gate refuses its own caller and BOTH cloud rails skip on every tick.\n' "$cfg" "$want"
    return 0
  fi
  deployed=1
  case "$rc" in
    __unreadable__)
                   printf 'UNREADABLE\tThe IDL journal could not be read, so this arm has NO VERDICT — not a clean one. Run this on the box that owns the sweep.\n' ;;
    '')            printf 'NO-ROWS\tThe IDL carries no cloud-return row at all: the sweep is not reaching this arm (job unloaded, dying earlier, or a different IDL path).\n' ;;
    skipped-config-divergence)
                   printf 'DIVERGENCE\tThe sweep itself filed skipped-config-divergence — it named the fault; the two paths disagreed at the moment it ran, even though they agree now.\n' ;;
    skipped-not-deployed)
                   printf 'NOT-DEPLOYED\tThe last row is skipped-not-deployed with the paths AGREEING now, so the copy that ran was a checkout or verifier copy, not the deployed one.\n' ;;
    skipped)       printf 'NOT-DEPLOYED\tThe last row is a bare skipped: cloud-return.sh is ABSENT from the deployed tree (NOT clean — the live layer has not converged).\n' ;;
    0)             printf 'RUNNING\tThe last pass completed. This arm is not the fault: rc 0 means the PASS ran — read the return ledger (§D) for what it did per session.\n' ;;
    4)             printf 'RUNNING\tThe last pass found the lock held by another pass. Normal under contention; only a persistent 4 is a jam.\n' ;;
    124)           printf 'RUNNING\tThe last pass was cut by its wall-clock bound; the next tick resumes. Only a persistent 124 means the pass cannot finish inside 900 s.\n' ;;
    *)             printf 'UNKNOWN\tThe last cloud_return_rc is %s, which this script has no arm for — read the row and the note field beside it.\n' "$rc" ;;
  esac
  : "$deployed"
}

if [ "${1:-}" = "--selftest" ]; then
  fails=0; checks=0
  expect() { checks=$((checks+1)); [ "$2" = "$1" ] || { fails=$((fails+1)); printf 'SELFTEST FAIL: %s (want %s, got %s)\n' "$3" "$1" "$2"; }; }
  tok() { verdict "$1" "$2" "$3" | cut -f1; }
  # 1-2. the hypothesis fires on a divergence, in both the expanded and the trailing-slash spelling,
  #      and does NOT fire when they agree — the control that makes the fire mean something.
  expect DIVERGENCE   "$(tok /Users/x/.claude-next /Users/x 0)"      'a diverging CLAUDE_CONFIG_DIR was not caught'
  expect DIVERGENCE   "$(tok /Users/x/.claude-next/ /Users/x 0)"     'a trailing slash hid the divergence'
  expect RUNNING      "$(tok /Users/x/.claude /Users/x 0)"           'agreeing paths with rc 0 did not read RUNNING'
  # 3. UNSET is the DEFAULT, not a divergence — the gate itself falls back to $HOME/.claude.
  expect RUNNING      "$(tok '' /Users/x 0)"                         'an unset CLAUDE_CONFIG_DIR was read as a divergence'
  # 4. a trailing slash on HOME must not manufacture one either.
  expect RUNNING      "$(tok /Users/x/.claude /Users/x/ 0)"          'a trailing slash on HOME manufactured a divergence'
  # 5-7. with the paths agreeing, the rc is what speaks — and each token is distinct, so a verdict
  #      that collapsed them all into one string could not pass this block.
  expect NOT-DEPLOYED "$(tok /Users/x/.claude /Users/x skipped-not-deployed)" 'skipped-not-deployed did not read NOT-DEPLOYED'
  expect NOT-DEPLOYED "$(tok /Users/x/.claude /Users/x skipped)"     'a bare skipped (tool absent) did not read NOT-DEPLOYED'
  expect NO-ROWS      "$(tok /Users/x/.claude /Users/x '')"          'no IDL row at all did not read NO-ROWS'
  # 8. the sweep's OWN token wins even when the paths agree by the time we look — the whole point of
  #    landing that token was that the fault is INTERMITTENT and need not still be present.
  expect DIVERGENCE   "$(tok /Users/x/.claude /Users/x skipped-config-divergence)" 'the sweep-filed divergence token was overridden by a now-clean compare'
  # 9. an rc with no arm ABSTAINS rather than guessing — no sensor, no verdict.
  expect UNKNOWN      "$(tok /Users/x/.claude /Users/x 77)"          'an unrecognised rc did not abstain'
  # 10. an UNREADABLE journal abstains too, and is DISTINCT from "readable, no rows" — off-box this
  #     is the difference between "no verdict" and a false claim about the operator's machine.
  expect UNREADABLE   "$(tok /Users/x/.claude /Users/x __unreadable__)" 'an unreadable journal was not distinguished from an empty one'
  if [ "$fails" = 0 ]; then
    echo "cloud-land-arm-diagnose --selftest: $checks/$checks — DIVERGENCE on a diverging config dir in two spellings and on the sweep's own filed token; GREEN on agreement, on UNSET (the documented default) and on a trailing slash either side; NOT-DEPLOYED, NO-ROWS and RUNNING each reached distinctly; UNKNOWN on an rc with no arm, and UNREADABLE distinct from NO-ROWS."
    exit 0
  fi
  echo "cloud-land-arm-diagnose --selftest: FAILED ($fails of $checks)."
  exit 1
fi

echo "cloud-land-arm-diagnose — read-only. Backlog f85fce7c26f5; evidence in docs/research/cloud-land-arm-step-2026-08-25.md"
echo "host: $(uname -s) · HOME=$HOME · CLAUDE_CONFIG_DIR=${CLAUDE_CONFIG_DIR:-<unset>}"
if [ "$(uname -s)" != "Darwin" ]; then
  echo
  echo "⚠ This is not the operator's box. launchctl and the plist do not exist here, and the reads"
  echo "  below will be empty. Run this on the Mac that owns com.chrisren.autonomy-sweep."
fi

hr; echo "A · the launchd job — is it loaded, and what environment does it carry?"
if command -v launchctl >/dev/null 2>&1; then
  _lc="$(launchctl print "gui/$(id -u)/$LABEL" 2>&1)"
  if [ -n "$_lc" ]; then
    printf '%s\n' "$_lc" | grep -iE 'state =|last exit code|program =|claude_config_dir|path =' | head -12
    printf '%s\n' "$_lc" | grep -qi 'claude_config_dir' || echo "  (the job's own environment sets no CLAUDE_CONFIG_DIR — it inherits whatever zsh -lc exports)"
  else
    echo "  launchctl print returned nothing — the job is not loaded for this uid."
  fi
else
  echo "  launchctl absent (not macOS) — UNREADABLE, not clean."
fi

hr; echo "B · what a LOGIN shell exports — the plist runs '/bin/zsh -lc', which sources .zshenv/.zprofile/.zlogin and NOT .zshrc"
if [ -x /bin/zsh ]; then
  /bin/zsh -lc 'echo "  CLAUDE_CONFIG_DIR=[${CLAUDE_CONFIG_DIR}]  HOME=[$HOME]"' 2>&1 | head -3
  _login_cfg="$(/bin/zsh -lc 'printf %s "${CLAUDE_CONFIG_DIR:-}"' 2>/dev/null)"
else
  echo "  /bin/zsh absent — UNREADABLE, not clean."
  _login_cfg=""
fi

hr; echo "C · the compare the gate actually makes"
_want="${_login_cfg:-$HOME/.claude}"; _want="${_want%/}"
echo "  \$0 (fixed by the plist)          : $PLIST_SPELLING"
echo "  \$_cc_cfg/scripts/autonomy-sweep.sh: $_want/scripts/autonomy-sweep.sh"
if [ "$PLIST_SPELLING" = "$_want/scripts/autonomy-sweep.sh" ]; then
  echo "  → they AGREE right now."
else
  echo "  → they DISAGREE right now. This is the fault."
fi

hr; echo "D · the sweep's own journal — every cloud_return_rc it has filed, newest first"
_last_rc="__unreadable__"
if [ -r "$IDL" ]; then
  _last_rc=""
  echo "  counts by rc (whole journal):"
  grep -o '"cloud_return_rc":"[^"]*"' "$IDL" 2>/dev/null | cut -d'"' -f4 | sort | uniq -c | sed 's/^/    /'
  echo "  last 12 rows:"
  grep '"cloud_return_rc"' "$IDL" 2>/dev/null | tail -12 | sed 's/^/    /' | cut -c1-160
  _last_rc="$(grep -o '"cloud_return_rc":"[^"]*"' "$IDL" 2>/dev/null | tail -1 | cut -d'"' -f4)"
  echo "  first time each rc appears (this is where the arm CHANGED):"
  for _rc in 0 4 124 skipped skipped-not-deployed skipped-config-divergence; do
    _first="$(grep "\"cloud_return_rc\":\"$_rc\"" "$IDL" 2>/dev/null | head -1 | grep -o '"ts":"[^"]*"' | cut -d'"' -f4)"
    [ -n "$_first" ] && printf '    %-26s %s\n' "$_rc" "$_first"
  done
else
  echo "  $IDL unreadable — UNREADABLE, not clean."
fi

hr; echo "E · the return ledger — rc 0 says the PASS ran, never that anything landed"
if [ -d "$CLOUD_DIR" ]; then
  echo "  declarations: $(find "$CLOUD_DIR" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
  for _f in return.jsonl land-refused.jsonl; do
    [ -r "$CLOUD_DIR/$_f" ] && { echo "  $_f (last 5):"; tail -5 "$CLOUD_DIR/$_f" | sed 's/^/    /' | cut -c1-160; }
  done
  find "$CLOUD_DIR" -maxdepth 1 -name '*.land-refused' 2>/dev/null | head -5 | sed 's/^/    refusal: /'
else
  echo "  $CLOUD_DIR absent — UNREADABLE, not clean."
fi

hr; echo "F · the divergence line, if the sweep has printed one (StandardErrorPath from the plist)"
if [ -r "$ERRLOG" ]; then
  grep -h 'CONFIG DIVERGENCE' "$ERRLOG" 2>/dev/null | tail -3 | sed 's/^/    /' | cut -c1-200
  grep -qh 'CONFIG DIVERGENCE' "$ERRLOG" 2>/dev/null || echo "    none — either the paths have agreed since that arm landed, or the sweep is not running."
else
  echo "  $ERRLOG unreadable."
fi

hr
_v="$(verdict "$_login_cfg" "$HOME" "$_last_rc")"
printf 'VERDICT: %s\n' "$(printf '%s' "$_v" | cut -f1)"
printf '  %s\n' "$(printf '%s' "$_v" | cut -f2-)"
echo
echo "If the verdict is DIVERGENCE: align CLAUDE_CONFIG_DIR with the plist, or the plist with it, then"
echo "confirm with one more run of this script — and the 116+ cloud branches already on origin will"
echo "land on the following ticks. If it is anything else, §D's 'first time each rc appears' is the"
echo "next thing to read: the arm changed on that date, and it is not this hypothesis."
