#!/bin/bash
# pane-spawn-coverage-lint — a RATCHET on pane-spawn sites that leave no row (item 1467ea1dad4f).
#
# WHY THIS IS A GATE AND NOT A DOC. `scripts/lib/pane-spawn-log.sh` exists to make exactly one
# inference sound:
#
#     a pane that exists with NO row in ~/.claude/logs/pane-spawns.jsonl was spawned by something
#     OUTSIDE this tree.
#
# That inference is what separates §S4.1's two surviving hypotheses — an unlogged caller vs an
# undocumented detached child — and it is only as good as COVERAGE. One uninstrumented spawn site
# downgrades it to "outside the tree, or that one site", which is the ambiguity being closed. A
# census that lives in a comment decays the first time someone adds a `launch`; a lint in the
# always-run gate phase cannot (memory `enforcement-must-live-at-the-chokepoint` — a check in its
# own suite is DETECTION; the gate is where it becomes a gate).
#
# THE RULE — narrow, and decidable from one file. A line that ISSUES a terminal-surface primitive
# must have a logger call within CC_PSC_WINDOW lines of it. Three primitive families, each chosen
# because it CREATES a surface rather than addressing one:
#
#   1. `launch --type=` / `launch --location=`   kitty remote-control window/tab/os-window creation
#   2. `create tab with` · `create window with` · `split vertically with` · `split horizontally with`
#                                                iTerm2 AppleScript surface creation
#   3. `detach-window` WITHOUT `--target-tab`    kitty: no target ⇒ a NEW OS window; with a target
#                                                it only re-homes an existing one and creates nothing
#
# `launch --type=background` is EXCLUDED from family 1 and that is a correctness point, not a
# convenience: kitty's `background` type runs a program with NO window at all. config/kitty.conf
# uses it to fire bin/kitty-pane-menu itself. Flagging it would demand a pane-spawn row for
# something that spawns no pane — and a rule that fires where its subject does not exist is the
# always-fires alarm (memory `alarm-polarity-and-attention-budget`).
#
# ── TWO TIERS, BECAUSE A PRIMITIVE AND THE LINE THAT ISSUES IT ARE OFTEN NOT THE SAME LINE ──────
# Measured over this tree: five of the 23 sites are DECLARATIONS, not invocations —
# `KARGS=(launch --type=os-window)` builds an argv issued 70 lines later; `set newTab to (create tab
# with default profile)` sits inside a heredoc whose `osascript` call is 24 lines above it. A pure
# proximity rule reports all five, every one a false positive, and a lint with a 5/23 false-positive
# rate is one people turn off. So:
#
#   TIER 1 (BLOCKING)  a primitive in a file with NO logger call anywhere. This is the case that
#                      actually matters — a new spawner, or an existing one nobody instrumented —
#                      and it has no false positives by construction.
#   TIER 2 (NOTICE)    a primitive whose file IS instrumented but whose own occurrence has no logger
#                      within the window. Printed, counted, never blocking.
#
# ⚠ STATED PLAINLY BECAUSE IT IS THE RULE'S REAL LIMIT: tier 2 means a SECOND, uninstrumented spawn
# added to an ALREADY-instrumented file is a notice and not a block. Closing that would need
# heredoc- and array-aware parsing in bash — more machinery than the check is worth, and machinery
# whose own failure mode is silent. The notice is the mitigation; it names the file and line.
#
# WHAT IS DELIBERATELY NOT FLAGGED, and why each exclusion is safe rather than convenient:
#   • CALLERS of an instrumented primitive — `it2 session split`, `handoff-fire.sh …`,
#     `kitty-split-launch.sh …`. The callee owns the row. Flagging callers too would demand a row
#     per LAYER, and "how many panes were spawned" would stop being a count anybody can take.
#   • `tests/` — fixtures and stubs spawn nothing real.
#   • This file and the library, which contain the patterns as data (self-exclusion, the same
#     treatment utc-stamp-lint.sh gives its own scar fixtures).
#   • The ALLOWLIST below — one entry, with its reason stated in-band so it cannot rot silently.
#
# Exit: 0 = every site covered · 1 = an uncovered site · 2 = bad usage / unreadable scan dir
#       (LOUD, never silent-green — an unreadable tree is not a clean tree)
#
# Env seams: CC_PSC_WINDOW (proximity lines, default 12) · CC_PSC_ALLOWLIST (overrides the embedded
# ratchet; set-EMPTY genuinely means "no exemptions", which `${VAR:-}` could not express) ·
# CC_PSC_OWN (newline-separated repo-relative paths; only these may BLOCK, everything else prints
# ADVISORY — this is what BOUNDS the gate at its ship-land.sh call site, so an uninstrumented
# spawner someone else left cannot freeze every land by everyone. Set-EMPTY is honored verbatim:
# a land that changed no scannable file blocks on nothing).
set -uo pipefail

WINDOW="${CC_PSC_WINDOW:-12}"
# Consume --selftest BEFORE $1 is read as a scan root, or the flag resolves to a directory named
# "--selftest" and the lint reports rc=2 on its own verification path.
SELFTEST=0
if [ "${1:-}" = "--selftest" ]; then SELFTEST=1; shift; fi
ROOT="${1:-$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")")/.." && pwd)}"

# The ratchet. `path::reason` — the reason is REQUIRED and is printed on every run, so an exemption
# has to keep justifying itself to whoever reads the gate output.
_default_allowlist() {
  cat <<'ALLOW'
scripts/terminal-bakeoff.sh::a one-off TERMINAL COMPARISON bench. Its surfaces are WezTerm and Ghostty windows plus a DETACHED private kitty instance on its own socket (`kitty --listen-on … --detach`), none of which can host an agent session — so a pane it makes can never be mistaken for one of the fleet's, which is the only confusion this lint exists to prevent.
ALLOW
}

if [ -n "${CC_PSC_ALLOWLIST+set}" ]; then ALLOWLIST="$CC_PSC_ALLOWLIST"; else ALLOWLIST="$(_default_allowlist)"; fi

# The logger call shapes that COUNT as coverage — TWO, and a per-file shim is deliberately NOT one
# of them.
#
# THE SHIM WAS TRIED AND IT BROKE SEVEN SUITES. The first version of this instrumentation defined a
# one-line `_spawn_log()` at the top of each file and called that. It went red immediately, because
# handoff-fire.sh's `as_tab`, `spawn_frontmost`, `it2py` and `mark_fired_peer` — and
# lr-reset-poller's `spawn_gui` — are sed-EXTRACTED as isolated units by their suites, which
# `eval` the function body with none of its file's top-level definitions present. A call to a
# top-level shim is then a `command not found` inside the unit under test: 41 failures, and
# handoff-fire.sh's own comments had already named the trap ("a new collaborator would be a 127
# under `set -e` — the trap this file has already paid for once").
#
# So the only accepted form is the one that survives extraction: an INLINE `command -v` guard around
# the library function. It depends on nothing but the library, and in an extracted context the guard
# short-circuits to a clean no-op. Accepting a shim spelling here would invite the same breakage back.
_covered_by() {
  grep -qE 'cc_log_pane_spawn|log_pane_spawn\(' <<<"$1"
}

rc=0 checked=0 flagged=0 noticed=0 advised=0
SELF_BASE="$(basename -- "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")")"

scan_dir() {
  local d="$1" f rel line n ctx file_covered
  [ -d "$ROOT/$d" ] || return 0
  while IFS= read -r f; do
    rel="${f#"$ROOT"/}"
    case "$(basename -- "$f")" in "$SELF_BASE"|pane-spawn-log.sh) continue ;; esac
    # Allowlisted?
    if printf '%s\n' "$ALLOWLIST" | grep -qF -- "$rel::"; then continue ;fi
    file_covered=0; _covered_by "$(cat "$f" 2>/dev/null)" && file_covered=1
    while IFS=: read -r n line; do
      [ -n "$n" ] || continue
      # Comment lines describe primitives; they do not issue them. Leading-# only, so an inline
      # trailing comment on a real launch still counts as the launch it is.
      case "$(printf '%s' "$line" | sed 's/^[[:space:]]*//')" in '#'*) continue ;; esac
      # `--type=background` runs a program with NO window — not a surface, so not a site.
      case "$line" in *--type=background*) continue ;; esac
      # `detach-window` is a primitive ONLY without a target tab.
      case "$line" in *detach-window*) case "$line" in *--target-tab*) continue ;; esac ;; esac
      checked=$((checked + 1))
      ctx="$(sed -n "$(( n > WINDOW ? n - WINDOW : 1 )),$(( n + WINDOW ))p" "$f" 2>/dev/null)"
      _covered_by "$ctx" && continue
      if [ "$file_covered" = 1 ]; then
        printf 'NOTICE %s:%s: primitive not within %s lines of a log call (file IS instrumented):\n    %s\n' \
          "$rel" "$n" "$WINDOW" "$(printf '%s' "$line" | sed 's/^[[:space:]]*//' | cut -c1-120)" >&2
        noticed=$((noticed + 1)); continue
      fi
      # OWN-SCOPE. CC_PSC_OWN unset ⇒ every finding blocks (the standalone/audit posture). SET,
      # including set to EMPTY, is honored verbatim: an empty own-set means this land changed no
      # scannable file, so nothing may block. Only a file in the set can turn rc red; everything
      # else prints as ADVISORY and is counted. This is what bounds the gate — see the
      # `gate_bounded:` markers at its ship-land.sh call site.
      if [ -n "${CC_PSC_OWN+set}" ] && ! printf '%s\n' "$CC_PSC_OWN" | grep -qxF -- "$rel"; then
        printf 'ADVISORY %s:%s: pane-spawn in a file with NO log call anywhere (outside this diff):\n    %s\n' \
          "$rel" "$n" "$(printf '%s' "$line" | sed 's/^[[:space:]]*//' | cut -c1-120)" >&2
        advised=$((advised + 1)); continue
      fi
      printf '%s:%s: pane-spawn in a file with NO log call anywhere:\n    %s\n' \
        "$rel" "$n" "$(printf '%s' "$line" | sed 's/^[[:space:]]*//' | cut -c1-120)" >&2
      flagged=$((flagged + 1)); rc=1
    done < <(grep -nE 'launch[[:space:]]+--type=|launch[[:space:]]+--location=|create tab with|create window with|split vertically with|split horizontally with|detach-window' "$f" 2>/dev/null || true)
  done < <(find "$ROOT/$d" -type f \( -name '*.sh' -o -name '*.py' -o ! -name '*.*' \) 2>/dev/null)
}

if [ "$SELFTEST" = 1 ]; then
  T="$(mktemp -d)" || exit 2
  trap 'rm -rf "$T"' EXIT
  mkdir -p "$T/scripts"
  pass=0 total=0
  _case() { # $1=name $2=expected-rc $3=file-body
    total=$((total + 1))
    printf '%s\n' "$3" > "$T/scripts/case.sh"
    ( CC_PSC_ALLOWLIST="" "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")" "$T" >/dev/null 2>&1 )
    local got=$?
    if [ "$got" = "$2" ]; then pass=$((pass + 1)); else echo "  selftest FAIL: $1 (want rc=$2, got rc=$got)" >&2; fi
  }
  # RED — an uncovered kitty launch, which is the exact shape of every site this item instrumented.
  _case "bare kitty launch is RED" 1 'kt launch --type=window --location=vsplit --cwd=current'
  # RED — the iTerm2 half. Both backends must be detectable or the rule is half a rule.
  _case "bare osascript create window is RED" 1 'osascript -e "set newWin to (create window with default profile)"'
  _case "bare osascript split vertically is RED" 1 'osascript -e "set p to (split vertically with default profile)"'
  # RED — detach-window with NO target creates an OS window.
  _case "untargeted detach-window is RED" 1 'kitty("detach-window", "--match", "id:3")'
  # GREEN — the two accepted forms, and only those.
  _case "covered by an inline command -v guard is GREEN" 0 \
    'command -v cc_log_pane_spawn >/dev/null 2>&1 && cc_log_pane_spawn split kitty 1 /tmp x
kt launch --type=window --cwd=current'
  _case "covered by python log_pane_spawn( is GREEN" 0 'log_pane_spawn("os-window","kitty","3","d")
kitty("detach-window", "--match", "id:3")'
  # RED — a per-file shim is NOT coverage. This is the extraction trap the header describes: it
  # LOOKS instrumented and is a `command not found` inside every sed-extracted unit test.
  _case "a per-file _spawn_log shim does NOT count as coverage" 1 '_spawn_log split kitty "" /tmp x
kt launch --type=window --cwd=current'
  # GREEN — a TARGETED detach re-homes an existing window and creates no surface.
  _case "targeted detach-window is GREEN" 0 'kitty("detach-window","--match","id:3","--target-tab","id:9")'
  # GREEN — a caller of an instrumented primitive is not itself a primitive.
  _case "a session-split CALLER is GREEN" 0 'it2 session split -s w0t0p0:42'
  # GREEN — prose describing a primitive is not one. Without this the lint would flag its own
  # documentation and every design comment in handoff-fire.sh.
  _case "a commented primitive is GREEN" 0 '# kt launch --type=window is what the split path used to do'
  # TIER 2 — a logger 40 lines away is a NOTICE, not a block, because the file IS instrumented.
  # This is the declaration shape (array literal / heredoc body) the tree really contains.
  _case "a logger beyond the window in an instrumented file is a NOTICE, not RED" 0 \
    "$(printf 'cc_log_pane_spawn split kitty 1 /tmp x\n%s\nkt launch --type=window\n' "$(for i in $(seq 1 40); do echo ": $i"; done)")"
  # …and the notice must actually be EMITTED, or tier 2 is silent absorption wearing a tier's name.
  total=$((total + 1))
  printf 'cc_log_pane_spawn split kitty 1 /tmp x\n%s\nkt launch --type=window\n' \
    "$(for i in $(seq 1 40); do echo ": $i"; done)" > "$T/scripts/case.sh"
  # CAPTURE, then match — never `… | grep -q`. Under `set -o pipefail` (line 65) grep -q exits on the
  # first match, SIGPIPEs the producer, and the pipeline's status becomes 141: the probe reads FALSE
  # precisely WHEN IT MATCHES. Measured here — this case failed while the notice was being printed
  # correctly (memory `pipefail-inverts-early-exit-probe`, 358 candidate sites in this tree).
  _nout="$(CC_PSC_ALLOWLIST="" "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")" "$T" 2>&1 >/dev/null || true)"
  case "$_nout" in
    *NOTICE*) pass=$((pass + 1)) ;;
    *) echo "  selftest FAIL: tier-2 notice was not printed" >&2 ;;
  esac
  # `--type=background` spawns no window, so it is not a site at all — in an UNinstrumented file,
  # which is the only condition under which a real site would block.
  _case "launch --type=background is not a site" 0 'kitty @ launch --type=background -- /bin/echo hi'
  # ── OWN-SCOPE, both directions. This is the clause that BOUNDS the gate, so an unverified one
  # would be a `gate_bounded:` marker asserting a budget nothing enforces.
  printf 'kt launch --type=window --cwd=current\n' > "$T/scripts/case.sh"
  total=$((total + 1))   # IN scope ⇒ still blocks
  ( CC_PSC_ALLOWLIST="" CC_PSC_OWN="scripts/case.sh" "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")" "$T" >/dev/null 2>&1 )
  [ $? = 1 ] && pass=$((pass + 1)) || echo "  selftest FAIL: an IN-scope violation must still block" >&2
  total=$((total + 1))   # OUT of scope ⇒ advisory, rc 0
  if ( CC_PSC_ALLOWLIST="" CC_PSC_OWN="scripts/somebody-else.sh" "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")" "$T" >/dev/null 2>&1 ); then
    pass=$((pass + 1))
  else echo "  selftest FAIL: an OUT-of-scope violation must not block" >&2; fi
  total=$((total + 1))   # …and it must SAY so, or the bound is silent absorption
  _aout="$(CC_PSC_ALLOWLIST="" CC_PSC_OWN="scripts/somebody-else.sh" "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")" "$T" 2>&1 >/dev/null || true)"
  case "$_aout" in
    *ADVISORY*) pass=$((pass + 1)) ;;
    *) echo "  selftest FAIL: an out-of-scope violation was silently dropped, not reported ADVISORY" >&2 ;;
  esac
  total=$((total + 1))   # set-EMPTY is honored verbatim: nothing in scope ⇒ nothing blocks
  if ( CC_PSC_ALLOWLIST="" CC_PSC_OWN="" "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")" "$T" >/dev/null 2>&1 ); then
    pass=$((pass + 1))
  else echo "  selftest FAIL: CC_PSC_OWN set-EMPTY must block on nothing" >&2; fi
  total=$((total + 1))   # UNSET ⇒ the standalone/audit posture, everything blocks
  ( CC_PSC_ALLOWLIST="" "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")" "$T" >/dev/null 2>&1 )
  [ $? = 1 ] && pass=$((pass + 1)) || echo "  selftest FAIL: CC_PSC_OWN UNSET must block on everything" >&2

  # LOUD on an unreadable root — a scan that cannot read must never report clean.
  total=$((total + 1))
  ( "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")" "$T/definitely-not-here" >/dev/null 2>&1 )
  [ $? = 2 ] && pass=$((pass + 1)) || echo "  selftest FAIL: missing root should exit 2" >&2
  if [ "$pass" = "$total" ]; then
    echo "pane-spawn-coverage-lint --selftest: $pass/$total — tier 1 RED on bare kitty/osascript/detach primitives in an uninstrumented file; tier 2 emits a NOTICE (not RED) for a declaration-shape site in an instrumented file; GREEN on both accepted call forms, a targeted detach, --type=background, a caller, and a comment; LOUD on an unreadable root; own-scope blocks INSIDE the diff, reports ADVISORY OUTSIDE it, honors set-EMPTY, and stays strict when unset."
    exit 0
  fi
  echo "pane-spawn-coverage-lint --selftest: $pass/$total FAILED — the detector does not discriminate." >&2
  exit 1
fi

[ -d "$ROOT" ] || { echo "pane-spawn-coverage-lint: scan root '$ROOT' is not a directory" >&2; exit 2; }
echo "pane-spawn-coverage-lint: scanning $ROOT (proximity ${WINDOW} lines)" >&2
if [ -n "$ALLOWLIST" ]; then
  printf '%s\n' "$ALLOWLIST" | while IFS= read -r a; do
    [ -n "$a" ] && printf '  allowlisted: %s\n    reason: %s\n' "${a%%::*}" "${a#*::}" >&2
  done
fi
for d in bin scripts hooks commands; do scan_dir "$d"; done
if [ "$rc" = 0 ]; then
  echo "pane-spawn-coverage-lint: OK — $checked pane-spawn site(s); $noticed tier-2 notice(s), $advised advisory (outside this diff)." >&2
else
  echo "pane-spawn-coverage-lint: RED — $flagged of $checked pane-spawn site(s) leave no row." >&2
  echo "  Every spawn must call cc_log_pane_spawn (scripts/lib/pane-spawn-log.sh), or the log's" >&2
  echo "  'no row ⇒ not from this tree' inference is false and §S4.1's ambiguity is back." >&2
fi
exit "$rc"
