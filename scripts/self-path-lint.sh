#!/bin/bash
# self-path-lint — a RATCHET on script-dir resolution.
#
# WHY: everything under ~/.claude/scripts/, ~/.claude/hooks/ and ~/.claude/bin/ is a REAL directory
# of PER-FILE SYMLINKS into this checkout. So for a script invoked through the live layer,
# `dirname "$0"` is ~/.claude/scripts — NOT the checkout — and `dirname "$0"/..` is ~/.claude, which
# has no tests/, no docs/, no .git. A script that derives its REPO ROOT that way and then uses
# repo-relative paths does not fail: it silently lints the wrong tree, or finds nothing and no-ops.
#
# Three incidents, one root cause:
#   · ship-land.sh (f8e40b4c577d, fixed f0a7f35) — resolved GATE_SELECT to ~/.claude/scripts/
#     gate-select.sh, which had no symlink yet, took the "missing ⇒ treating as FULL (fail-closed)"
#     branch, and ran the whole ~1630-test suite on EVERY live-path land, unserialized across every
#     landing worktree. That is the amplifier in the 2026-07-26 machine-wide gate runaway. It looked
#     INTERMITTENT because `./scripts/ship-land.sh` from a worktree found its sibling and went
#     scoped, while the same land via the live symlink went FULL.
#   · deploy-parity-assert.sh (816015ecb30b) — same shape.
#   · test-hermeticity-lint.sh (2026-07-26) — its ROOT landed in ~/.claude, so --selftest failed for
#     a reason that had nothing to do with the ratchet it exists to enforce.
#
# WHY A RATCHET AND NOT A FLAG-DAY: the sweep behind this lint found 26 files carrying the shape
# today, all LATENT (only 2 are launchd-invoked, and both dodge it — lead-supervisor's plist uses the
# checkout path, rotate-autonomy-logs has a tolerant fallback chain). Rewriting 26 files to fix
# nothing that is currently breaking is a worse change than the one it prevents, and a lint nobody
# can turn on is worth zero. So the existing 26 are grandfathered BY PATH and the rule binds only
# where it is free — NEW code. The list can only SHRINK: fixing a file is a two-line change (resolve
# $0, delete its allowlist line) and the lint FAILS if you fix one and forget to delete the line,
# which is what stops a ratchet from silently becoming a permanent exemption list.
#
# THE RULE: a line violates iff it derives a path by `..` TRAVERSAL from a `dirname` of an
# UNRESOLVED $0 / $BASH_SOURCE. Scoped deliberately:
#   · `..` traversal only. `SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"` is FINE — it
#     re-execs the script itself, and the symlink resolves to that same script. A sibling in the
#     SAME directory (`$(dirname "$0")/foo.sh`) is the Class-1 shape, which is swept to zero today
#     and is what deploy-link-parity.sh already covers; only `..` reaches a tree that is not deployed.
#   · UNRESOLVED only. Once $0 is resolved the expression reads `dirname "$SELF"`, which does not
#     match — so the rule and its fix are the same edit, on the same line.
#   · A GUARDED CANDIDATE with a config-dir alternative is not a violation. The distinction that
#     matters is guarded-vs-unconditional, not the syntax of the ladder: a self-derived path that is
#     TESTED for existence and backed by a $HOME/.claude / $CLAUDE_CONFIG_DIR rung degrades to the
#     live copy instead of resolving to the wrong tree (rotate-autonomy-logs.sh, the hooks/lib source
#     ladders, delivery-verify.sh's resolve_*). A self-derived path consumed UNCONDITIONALLY is the
#     defect, however many $HOME/.claude paths happen to sit near it — nightly-regression.sh:55
#     derives REPO with no test and then builds $REPO/tests, $REPO/launchd/*.plist from it, so a
#     wrong root silently mis-targets every one. (Resolving $0 is still better than any ladder — a
#     ladder collapses to ONE surviving path under ~/.claude, memory:
#     shared-lib-source-ladder-collapses-when-deployed — but it does not SILENTLY read the wrong
#     tree, so it is not this lint's business.)
#
# WHY NOT KEY ON "is this file symlinked into ~/.claude today": because that makes the verdict a
# function of DEPLOY STATE, so a file goes red/green without changing. It is also exactly the fact
# that made ship-land's bug intermittent. The rule is uniform over the deployed LAYERS by directory.
#
# Exit: 0 = clean · 1 = violation · 2 = bad usage / unusable scan tree / unrunnable check (LOUD,
# never silent-green).
#
# Env seams: CC_SELFPATH_ALLOWLIST overrides the embedded allowlist (selftest) · CC_SELFPATH_OWN
# narrows which violations BLOCK (see the own-scope note below).
#
# THREE TIERS OF EXEMPTION, deliberately distinct — collapsing them is how a ratchet rots:
#   · the RATCHET (EMBEDDED_ALLOWLIST) — a genuine latent violation that SHOULD be fixed one day.
#     Delete-only, and the lint goes red if the file is fixed and its line survives.
#   · the `self_path_ok` MARKER — a line reviewed as CORRECT that the structural rules cannot see:
#     the shape carried as DATA (a fixture, a doc string), or a fallback guarded in a form this lint
#     does not model (hooks/lib/session-index-helpers.sh:27 is the else-branch of an explicit
#     readlink guard; completion-push.sh:124 falls back through a function call, not an inline rung).
#     Accepted as a trailing marker or on the nearest preceding comment line, and it must carry a
#     REASON. Never use it to silence a real violation — that is what the ratchet is for.
#   · the LAYER/SUBTREE scope — code the live symlink layer cannot reach at all, so the shape cannot
#     bite it. Not an exemption so much as an absence of jurisdiction.
#
# SC2016 is disabled FILE-WIDE below, which is unusual and deliberate. Nearly every string in this
# file — the detector patterns, the fix guidance, and every --selftest fixture — must contain the
# LITERAL text `$0` / `${BASH_SOURCE[0]}` and must NOT expand it; expansion would substitute this
# script for the sample being matched and quietly destroy the fixtures. The gate runs `shellcheck`
# bare (ship-land.sh:999), so at default severity 17 such infos would be a hard RED. Per-line
# directives would outnumber the code. (Note the capital in "ShellCheck" wherever this file discusses
# the tool in prose: a comment whose first word is the lowercase directive name is parsed as a
# MALFORMED DIRECTIVE and aborts analysis of the entire file. Memory slug for that scar:
# `shellcheck-prose-comment-aborts-analysis` — and note it had to be backticked HERE, mid-line,
# because writing it at the start of a wrapped comment line reproduced the bug while documenting it.)
# shellcheck disable=SC2016
set -uo pipefail

# Resolve $0 THROUGH symlinks before deriving ROOT — this lint must eat its own dog food, and for
# the exact reason it exists: invoked as ~/.claude/scripts/self-path-lint.sh, a bare
# `dirname "$0"/..` would make it scan ~/.claude and find no layers at all. macOS ships the BSD
# userland, so there is no `readlink -f`; the manual loop is the portable form (bash 3.2 safe).
_resolve_self() {  # <path> → absolute path, every symlink hop resolved
  local p="$1" d
  while [ -L "$p" ]; do
    d="$(cd "$(dirname "$p")" && pwd)"
    p="$(readlink "$p")"
    case "$p" in /*) ;; *) p="$d/$p" ;; esac
  done
  printf '%s/%s\n' "$(cd "$(dirname "$p")" && pwd)" "$(basename "$p")"
}
SELF="$(_resolve_self "${BASH_SOURCE[0]:-$0}")"
ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"

# The symlink-deployed layers. A file outside these is not reached through ~/.claude by a per-file
# symlink, so the shape cannot bite it.
LAYERS="scripts hooks bin"

# ── the ratchet: paths grandfathered with an unresolved self-derived repo root. ────────────────────
# ONLY EVER DELETE LINES FROM THIS LIST. Repo-relative paths, as reported.
EMBEDDED_ALLOWLIST="$(cat <<'ALLOW'
bin/cc-classify
scripts/alarm-polarity-lint.sh
scripts/boundary-hook-e2e.sh
scripts/comms-safety-gate.sh
scripts/effort-parity-assert.sh
scripts/launchd-parity-lint.sh
scripts/lead-deathwatch.sh
scripts/lead-reconciler.sh
scripts/limit-reset-safety-gate.sh
scripts/nightly-regression.sh
scripts/p8-e2e.sh
scripts/pane-id-lint.sh
scripts/power-policy-verify.sh
scripts/premortem-gate.sh
scripts/reaper-e2e.sh
scripts/reaper-horizon-lint.sh
scripts/reaper-safety-gate.sh
scripts/relogin-desharing-activate.sh
scripts/respawn-safety-gate.sh
scripts/route-safety-gate.sh
scripts/session-lifecycle-safety-gate.sh
scripts/supervisor-e2e.sh
scripts/telemetry-e2e.sh
scripts/wait-contract-lint.sh
scripts/wait-safety-gate.sh
ALLOW
)"

# ── the detector ──────────────────────────────────────────────────────────────────────────────────
# ONE awk pass per file, deliberately: the precedent lints built this predicate out of piped greps
# and then needed retry machinery because under fork pressure a `grep` that could not RUN was
# indistinguishable from "no match", and the ratchet FABRICATED violations naming good files
# (memory: named-failure-vs-no-verdict). One fork has no such pipeline, and awk reports "I could not
# run" as a non-zero exit, which is a different signal from "I found nothing" — so the third state is
# structural here rather than reconstructed.
#
# Full-line comments are stripped BEFORE matching. Load-bearing: six files in this repo DISCUSS
# `dirname "$0"` in prose (this header included, ship-land.sh:126, test-hermeticity-lint.sh:27,
# bats-shellcheck-lint.sh:119, never-stuck-gate.sh:39, host-suites.manifest:144). A detector that
# matches text ABOUT the defect reports the fix as the bug (memory:
# detector-matching-its-own-skill-description).
#
# Tolerance is judged over the CONSTRUCT, not one line, in two forms:
#
#   (1) a LADDER — the flagged line plus every line it continues onto via a trailing backslash. If a
#       config-dir anchor appears anywhere in it, a wrong first rung is skipped, not used.
#       (`for cand in "$(dirname "$0")/../lib/x" \ "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/lib/x"; do`)
#
#   (2) a GUARDED CANDIDATE — the flagged line assigns a variable, and within the following window
#       that variable is TESTED as a path (`[ -x "$sd/bin/cc-announce" ]`, `[[ -f "$HOOK" ]]`) while a
#       config-dir anchor is offered in the same window. That is the if/elif/else form of the same
#       ladder (completion-push.sh, delivery-verify.sh) and the `[[ -f "$HOOK" ]] || HOOK=…` form
#       (cc-crash-report:29).
#
# THE EXISTENCE TEST IS THE LOAD-BEARING HALF, not the nearby anchor. Dropping it and accepting "a
# $HOME/.claude path appears within N lines" would exempt nightly-regression.sh:55, which derives
# REPO unconditionally and merely happens to assign PAGEDIR and LOG under $HOME/.claude on the next
# two lines — a coincidence of layout, not a fallback. A path nobody tests is a path nobody can fall
# back from.
unresolved_self_paths() {  # <file> → "line:text" per violation; rc 0 = ran, non-0 = could not run
  awk '
    BEGIN { WINDOW = 8 }   # far enough to span an if/elif/else resolver, short enough to stay local
    { n++; line[n] = $0 }
    function is_comment(s) { return s ~ /^[[:space:]]*#/ }
    function derives_self_parent(s) {
      # a dirname of a bare $0 / ${0} / $BASH_SOURCE / ${BASH_SOURCE[0]} ...
      if (s !~ /dirname[[:space:]]+"?\$\{?(0|BASH_SOURCE)/) return 0
      # ... combined with a parent-directory traversal on the same expression.
      return (s ~ /\/\.\./)
    }
    function has_config_anchor(s) {
      # The brace spellings are NOT cosmetic variants to be tolerated grudgingly — ${HOME:-} is the
      # STRICTER form. A ladder is one for-list, and bash expands the WHOLE list before the loop body
      # runs, so a bare $HOME rung under `set -u` aborts the script on the third candidate even when
      # the first one resolves — the fallback kills the caller instead of degrading (d5f97f9a, and
      # the 5 sibling copies). Keying this predicate on the literal `$HOME/` spelling made the safest
      # rung read as NO anchor at all, so hardening a ladder turned it into a fresh violation: the
      # guard penalised its own fix. Match the CLASS (a HOME-anchored config rung), never one
      # spelling of it (memory: denylist-enumerates-spellings-not-the-class).
      return (s ~ /\$\{?HOME(:-[^}]*)?\}?\/\.claude/ || s ~ /CLAUDE_CONFIG_DIR/)
    }
    END {
      for (i = 1; i <= n; i++) {
        s = line[i]
        if (is_comment(s)) continue
        if (!derives_self_parent(s)) continue
        # Explicit escape hatch, accepted EITHER as a trailing marker on the line itself OR on the
        # nearest preceding comment line -- the same placement freedom as a shellcheck directive,
        # because the lines this fires on are often already at the margin and the reason needs room.
        if (s ~ /self_path_ok/) continue
        hatch = 0
        for (k = i - 1; k >= 1; k--) {
          if (line[k] ~ /^[[:space:]]*$/) continue
          if (!is_comment(line[k])) break
          if (line[k] ~ /self_path_ok/) { hatch = 1; break }
        }
        if (hatch) continue

        # (1) LADDER: this line + every line it continues onto via a trailing backslash
        c = s; j = i
        while (j <= n && line[j] ~ /\\[[:space:]]*$/) { j++; c = c "\n" line[j] }
        if (has_config_anchor(c)) continue

        # (2) GUARDED CANDIDATE: the line assigns VAR; within WINDOW lines after the construct, VAR
        # is tested as a path AND a config-dir alternative is offered. Both halves required.
        # Which variable receives the path? Take the RIGHTMOST NAME= to the LEFT of the dirname, not
        # a line-anchored match. The house idiom splits the declaration from the assignment --
        # "local sd; sd=$(...)" -- so that local cannot mask the exit status of the substitution, and
        # a column-0 anchor finds no assignment at all on such a line. That would silently skip the
        # guarded-candidate check below and report every resolver written this way as a violation.
        # (No apostrophes in this awk program: it is single-quoted, so one would end the string.)
        v = ""
        pre = substr(s, 1, index(s, "dirname") - 1)
        while (match(pre, /[A-Za-z_][A-Za-z0-9_]*=/)) {
          v = substr(pre, RSTART, RLENGTH)
          pre = substr(pre, RSTART + RLENGTH)
        }
        sub(/=$/, "", v)
        if (v != "") {
          tested = 0; anchored = 0
          for (k = j + 1; k <= n && k <= j + WINDOW; k++) {
            w = line[k]
            if (is_comment(w)) continue
            # a path test naming this variable: [ -x "$sd/bin/x" ] / [[ -f "$HOOK" ]] / [ -e "$v" ]
            if (w ~ ("\\[+[[:space:]]*-[fxer][[:space:]]+\"?\\$\\{?" v "[^A-Za-z0-9_]")) tested = 1
            if (has_config_anchor(w)) anchored = 1
          }
          if (tested && anchored) continue
        }
        printf "%d:%s\n", i, s
      }
    }
  ' "$1"
}

# ── COULD-NOT-CHECK is a THIRD state, never a verdict ─────────────────────────────────────────────
# A run whose detector could not execute has nothing to say about the tree. It must exit 2
# (unusable) — NOT 1, which every caller reads as "your tree is dirty", and not 0, which would be a
# silent green. Same discipline as the unusable-scan-tree path below, and the repo's standing rule
# that gate-never-ran is not gate-red.
CHECK_FAILED=0

# ── OWN-SCOPE — which violations may BLOCK, as distinct from which are REPORTED ────────────────────
# The rule is "do not ADD an unresolved self-path". Enforcing it over the WHOLE tree would make
# every lander answerable for every other lander's file, and because trunk is shared that is a
# FLEET-WIDE hard stop (memory: whole-tree-lint-is-a-fleet-wide-hard-stop; GATE_ARCHITECTURE_PLAN §9
# measures the cost at 66% → 30% land rate). The full tree is still scanned and every violation
# still printed — one outside the set is LABELLED, never hidden — only the EXIT CODE narrows.
#
# THREE states, not two, and `${VAR:-}` cannot express them — this is the bug this comment exists to
# prevent recurring. ABSENT own-set ⇒ strict, judge the whole tree (a bare human run, the postland
# net). PRESENT BUT EMPTY ⇒ "this land changes no file in these layers", so NOTHING may block — the
# docs-only land. Presence is carried by ARGUMENT COUNT here and by `${CC_SELFPATH_OWN+set}` at the
# entrypoint.
# EXACT-LINE MEMBERSHIP WITHOUT A FORK. The obvious `printf '%s\n' "$2" | grep -qxF "$1"` costs two
# forks and runs for EVERY scanned file (the no-hits branch below asks "is this file still
# grandfathered?"), which on the real tree is ~660 forks of pure overhead. Wrapping both the haystack
# and the needle in newlines makes a plain shell pattern match do the same exact-line test with none.
# This is not micro-tuning for its own sake: the lint runs inside every land, on a box that routinely
# sits at load 20+, where forks are the scarce resource — and the sibling ratchets needed retry
# machinery precisely because their predicates were fork-bound and died under that pressure.
in_list() {  # $1=needle line · $2=newline-delimited haystack
  case "
$2
" in
    *"
$1
"*) return 0 ;;
  esac
  return 1
}

in_own() {  # $1=rel path · $2=own-set text · $3=1 if an own-set was supplied at all
  [ "${3:-0}" = "1" ] || return 0          # no own-set supplied ⇒ everything is own ⇒ strict
  [ -n "$2" ] || return 1                  # supplied but empty ⇒ nothing is own ⇒ nothing blocks
  in_list "$1" "$2"
}

in_allowlist() {  # $1=rel path · $2=allowlist text
  in_list "$1" "$2"
}

# ── is this file shell at all ─────────────────────────────────────────────────────────────────────
# bin/ is entirely extensionless, so extension alone cannot decide. A shebang read is the only honest
# test, and it is what ship-land's own changed-file linter uses. Read via the `read` builtin rather
# than `head -n1 | grep`: same answer, two fewer forks per file.
is_shell() {
  case "$1" in *.sh) return 0 ;; *.py|*.pyc|*.md|*.json|*.yaml|*.yml|*.conf|*.manifest|*.plist|*.txt) return 1 ;; esac
  local first=""
  # rc is deliberately ignored: a single-line file with no trailing newline sets `first` and still
  # returns non-zero, and that file is exactly the kind this has to classify correctly.
  IFS= read -r first < "$1" 2>/dev/null
  case "$first" in
    '#!'*bash*|'#!'*/bin/sh*|'#!'*"env sh"*) return 0 ;;
  esac
  return 1
}

# lint_tree <root> <allowlist-text> [own-set-text] — 0 clean · 1 violations · 2 unusable
lint_tree() {
  local root="$1" allow="$2" own="${3:-}" own_scoped=0
  local f rel hits bad=0 seen=0 other=0 stuck=0 layer found_layer=0
  [ "$#" -ge 3 ] && own_scoped=1
  CHECK_FAILED=0
  [ -d "$root" ] || { echo "self-path-lint: ⛔ not a directory: $root" >&2; return 2; }

  local dirs=""
  for layer in $LAYERS; do
    [ -d "$root/$layer" ] && { dirs="$dirs $root/$layer"; found_layer=1; }
  done
  [ "$found_layer" -eq 1 ] || {
    echo "self-path-lint: ⛔ none of the deployed layers ($LAYERS) exist under $root" >&2; return 2; }

  # shellcheck disable=SC2086  # $dirs is a deliberate word-split list of scan roots (see below)
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    # A tests/ subtree is never symlink-deployed: install.sh re-globs hooks/*.sh, hooks/lib/*.sh,
    # scripts/*.sh, bin/* — not hooks/tests/. ~/.claude/hooks/tests does not exist, and a test always
    # runs from a checkout (bats resolves its own root from $BATS_TEST_FILENAME). So the live layer
    # cannot reach these files at all, and the shape cannot bite them.
    case "$f" in */.git/*|*/tests/*) continue ;; esac
    # A DETECTOR MUST NOT SCAN ITSELF. This file necessarily CONTAINS the shape it hunts: the
    # --selftest fixtures replay the real f8e40b4c577d / 816015ecb30b lines, because a control that
    # hand-approximates the artifact passes vacuously (memory: control-must-replay-the-real-
    # artifact), and rewriting them to dodge the regex would destroy the property that makes them a
    # valid control. What validates THIS file is --selftest, which the gate runs alongside the scan.
    case "${f##*/}" in self-path-lint.sh) continue ;; esac   # ${f##*/} not basename: one less fork
    is_shell "$f" || continue
    seen=$((seen + 1))
    rel="${f#"$root"/}"

    hits="$(unresolved_self_paths "$f")" || {
      CHECK_FAILED=1
      echo "self-path-lint: ⛔ detector could not RUN for $rel" >&2
      continue
    }

    if [ -n "$hits" ]; then
      if in_allowlist "$rel" "$allow"; then
        continue
      elif in_own "$rel" "$own" "$own_scoped"; then
        printf '  SELF-PATH %s\n' "$rel"
        printf '%s\n' "$hits" | sed 's/^/              /'
        bad=$((bad + 1))
      else
        printf '  selfpath? %s (NOT in your diff — advisory, not blocking)\n' "$rel"
        other=$((other + 1))
      fi
    elif in_allowlist "$rel" "$allow"; then
      if in_own "$rel" "$own" "$own_scoped"; then
        printf '  RATCHET   %s resolves $0 now — delete its allowlist line\n' "$rel"
        stuck=$((stuck + 1))
      else
        printf '  ratchet?  %s is fixed but still grandfathered (NOT in your diff — advisory)\n' "$rel"
        other=$((other + 1))
      fi
    fi
  done <<EOF
$(find $dirs -type f 2>/dev/null)
EOF

  [ "$seen" -gt 0 ] || { echo "self-path-lint: ⛔ no shell files under $root ($LAYERS)" >&2; return 2; }
  [ "$other" -eq 0 ] || echo "self-path-lint: $other pre-existing item(s) NOT in your diff — reported, not blocking (own-scope)."

  # Checked AFTER the own-scope report so a killed detector cannot masquerade as a clean own-scope
  # pass: own-scope narrows WHICH violations block, it never makes an unrunnable check trustworthy.
  if [ "$CHECK_FAILED" -ne 0 ]; then
    echo "self-path-lint: ⛔ UNUSABLE — the detector failed to run (see above); no verdict." >&2
    echo "  This is NOT a violation report. Re-run when the box is quieter; do not 'fix' any file on it." >&2
    return 2
  fi

  if [ "$bad" -gt 0 ]; then
    echo "self-path-lint: ⛔ $bad file(s) above derive a path via '..' from an UNRESOLVED \$0."
    echo "  Why it matters: ~/.claude/{scripts,hooks,bin}/ are per-file SYMLINKS into the checkout, so"
    echo "  through the live layer \`dirname \"\$0\"/..\` is ~/.claude — no tests/, no docs/, no .git."
    echo "  The script does not fail; it reads the WRONG TREE or silently no-ops, and only on the live"
    echo "  path, so the bug is invisible from a worktree (ship-land f8e40b4c577d ran the full ~1630-"
    echo "  test suite on every live-path land for exactly this reason)."
    echo "  Fix: resolve \$0 through its symlinks FIRST, then derive — the canonical loop is"
    echo "  _resolve_self() in scripts/ship-land.sh (no \`readlink -f\`: that is GNU-only, this box is BSD):"
    echo "      while [ -L \"\$p\" ]; do d=\"\$(cd \"\$(dirname \"\$p\")\" && pwd)\"; p=\"\$(readlink \"\$p\")\";"
    echo "        case \"\$p\" in /*) ;; *) p=\"\$d/\$p\" ;; esac; done"
    echo "      SELF=…; ROOT=\"\$(cd \"\$(dirname \"\$SELF\")/..\" && pwd)\""
    echo "  A line that carries the shape as DATA (a fixture, a doc example) takes a trailing"
    echo "  \`self_path_ok\` marker instead. Do NOT add to the allowlist."
  fi
  if [ "$stuck" -gt 0 ]; then
    echo "self-path-lint: ⛔ $stuck file(s) above are fixed but still grandfathered."
    echo "  Fix: delete their lines from EMBEDDED_ALLOWLIST in $SELF — the ratchet only shrinks."
  fi
  [ $((bad + stuck)) -eq 0 ] || return 1
  echo "self-path-lint: clean — $seen shell file(s) scanned; $(printf '%s\n' "$allow" | grep -c .) grandfathered, 0 new unresolved self-paths."
  return 0
}

# ── --selftest: every case proves a RED path FIRES or a GREEN path does NOT, both directions ───────
# A detector is only worth its clean verdict if it can be shown to discriminate; a control that
# cannot fail the same way as the real thing passes vacuously.
if [ "${1:-}" = "--selftest" ]; then
  d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT
  fails=0
  # mk <case> <basename> <body> — a scan root $d/<case> with one file under scripts/
  mk() { mkdir -p "$d/$1/scripts"; { printf '#!/bin/bash\n'; printf '%s\n' "$3"; } > "$d/$1/scripts/$2"; }

  # ── THE CONTROLS ARE THE REAL ARTIFACTS, recovered from the scars they came from ───────────────
  # (a) the deploy-parity-assert.sh / safety-gate shape: cd to a self-derived repo root.
  mk cd_parent probe.sh 'cd "$(dirname "$0")/.." || exit 2'
  # (b) the ship-land f8e40b4c577d shape: a sibling resolved through an unresolved parent.
  mk assign_root probe.sh 'ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GATE_SELECT="$ROOT/scripts/gate-select.sh"'
  # (c) the same via ${BASH_SOURCE[0]} — a different spelling of one defect.
  mk bash_source probe.sh 'REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"'

  # ── THE GREEN CASES — each is a shape that MUST NOT be flagged ─────────────────────────────────
  # (d) the FIX: resolve first, then traverse. This is the same `..` traversal as (b), so it proves
  #     the rule keys on RESOLVEDNESS and not merely on the presence of '..'.
  mk resolved probe.sh 'SELF="$0"
while [ -L "$SELF" ]; do SELF="$(readlink "$SELF")"; done
ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"'
  # (e) self re-exec — no '..', and the symlink resolves to this same script. Benign, and ~30 files
  #     in this repo do it; flagging them would bury the real signal.
  mk selfexec probe.sh 'SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"'
  # (f) own-directory sibling (Class-1) — deliberately out of scope; deploy-link-parity covers it.
  mk sibling probe.sh 'HF="$(cd "$(dirname "$0")" && pwd)/handoff-fire.sh"'
  # (g) a tolerant fallback ladder across continuation lines — rotate-autonomy-logs / hooks/lib.
  mk ladder probe.sh 'for c in "$(dirname "$0")/../hooks/lib/page-damp.sh" \
        "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/page-damp.sh" \
        "$HOME/.claude/hooks/lib/page-damp.sh"; do
  [ -f "$c" ] && { . "$c"; break; }
done'
  # (g2) the SAME ladder with the set -u-safe `${HOME:-}` rung — the cc-kitty-bin resolver shape in
  #      handoff-fire.sh / boot-resume-launch.sh / render-census.sh / lr-handoff.sh /
  #      lr-reset-poller.sh. It must be AT LEAST as tolerated as (g): a bare $HOME rung aborts the
  #      whole script under set -u before the loop body ever runs, so this is the hardened form. Held
  #      as its own case because (g) can never fail on it — (g) carries a bare $HOME rung of its own,
  #      which would satisfy the predicate no matter how the brace spelling is treated (memory:
  #      sibling-guard-makes-the-fixture-vacuous).
  mk ladder_braced probe.sh 'for c in "$(dirname "$0")/../bin/cc-kitty-bin" \
        "${HOME:-}/.claude/bin/cc-kitty-bin"; do
  [ -x "$c" ] && break
done'
  # (h) same-variable config-dir reassignment on the NEXT line — cc-crash-report:29.
  mk nextline probe.sh 'HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/hooks/w.sh"
[[ -f "$HOOK" ]] || HOOK="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/w.sh"'
  # (h2) the if/elif/else spelling of the same ladder — completion-push.sh / delivery-verify.sh.
  #      Tolerant, and NOT reachable by a continuation-line scan, which is why the guarded-candidate
  #      rule exists at all.
  mk ifelse probe.sh 'resolve_announce() {
  local sd; sd="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/.."
  if   [ -x "$sd/bin/cc-announce" ]; then echo "$sd/bin/cc-announce"
  elif command -v cc-announce >/dev/null 2>&1; then command -v cc-announce
  else echo "$HOME/.claude/bin/cc-announce"; fi
}'
  # (h3) THE OTHER DIRECTION, and the case that decides the whole rule: nightly-regression.sh:55.
  #      An UNCONDITIONAL self-derived root whose next lines merely happen to anchor OTHER variables
  #      under $HOME/.claude. Nothing tests $REPO, so nothing can fall back from it — a wrong root
  #      silently mis-targets every path built on it. If (h2) passes by "an anchor appears nearby",
  #      this passes too, and the rule is worthless. It must go RED.
  mk unguarded probe.sh 'REPO="${CC_NIGHTLY_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PAGEDIR="${CC_NIGHTLY_PAGEDIR:-$HOME/.claude/autonomy/pages}"
LOG="${CC_NIGHTLY_LOG:-$HOME/.claude/autonomy/regression.log}"
BATS_DIR="${CC_NIGHTLY_BATS_DIR:-$REPO/tests}"'
  # (i) PROSE about the defect must not be a finding — this is the trap that made a sibling detector
  #     open false packets off its own description (memory: detector-matching-its-own-skill-description).
  mk prose probe.sh '# a bare `cd "$(dirname "$0")/.."` here would be the 816015ecb30b scar
ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"'
  # (j) the escape hatch, in both accepted placements.
  mk marker probe.sh 'EXAMPLE=$(printf %s "cd \"$(dirname \"$0\")/..\"")  # self_path_ok — doc string'
  mk marker_above probe.sh '# self_path_ok — reviewed: the guard is structural, see the branch above
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"'
  # (j2) …and a comment that does NOT carry the marker must not shield the line under it, or every
  #      commented line in the repo becomes an exemption.
  mk marker_absent probe.sh '# an ordinary explanatory comment
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"'
  # (k) a NON-shell file carrying the shape (host-suites.manifest does) must not be scanned.
  mkdir -p "$d/nonshell/scripts"
  printf '# cd "$(dirname "$0")/.." — prose in a manifest\n' > "$d/nonshell/scripts/x.manifest"
  printf '#!/bin/bash\ntrue\n' > "$d/nonshell/scripts/ok.sh"
  # (k2) a tests/ SUBTREE is never symlink-deployed, so the shape cannot bite there.
  mkdir -p "$d/subtree/hooks/tests"
  printf '#!/bin/bash\nREPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"\n' > "$d/subtree/hooks/tests/t.test.sh"
  printf '#!/bin/bash\ntrue\n' > "$d/subtree/hooks/ok.sh"

  # The reported case count is COUNTED, never typed: a hardcoded total silently drifts as cases are
  # added, and a selftest that misreports its own coverage is the last place to keep a stale number.
  checks=0
  expect() {  # <want-rc> <got-rc> <failure message>
    checks=$((checks + 1))
    [ "$2" -eq "$1" ] || { echo "SELFTEST FAIL: $3"; fails=1; }
  }
  red()   { lint_tree "$d/$1" "${2-}" >/dev/null 2>&1; expect 1 "$?" "$3"; }
  green() { lint_tree "$d/$1" "${2-}" >/dev/null 2>&1; expect 0 "$?" "$3"; }

  red   cd_parent   "" "a self-derived \`cd ..\` did not go RED"
  red   assign_root "" "a self-derived ROOT= (the ship-land shape) did not go RED"
  red   bash_source "" "the \${BASH_SOURCE[0]} spelling did not go RED"
  green resolved    "" "a RESOLVED \$0 with the same '..' traversal was flagged — the rule is keying on '..', not on resolvedness"
  green selfexec    "" "a self re-exec (no '..') was flagged"
  green sibling     "" "an own-directory sibling (Class-1, out of scope) was flagged"
  green ladder      "" "a tolerant fallback ladder was flagged"
  green ladder_braced "" "a fallback ladder whose config rung is the set -u-safe \${HOME:-} spelling was flagged — the predicate is keying on the literal \$HOME spelling, so hardening a ladder mints a violation"
  green nextline    "" "a same-variable config-dir fallback on the next line was flagged"
  green ifelse      "" "an if/elif/else guarded-candidate resolver was flagged"
  red   unguarded   "" "an UNCONDITIONAL self-derived root with unrelated \$HOME/.claude lines nearby went GREEN — tolerance is keying on a nearby anchor instead of on an existence test"
  green prose       "" "PROSE about the defect was reported as the defect"
  green marker       "" "a trailing self_path_ok marker did not suppress"
  green marker_above "" "a self_path_ok marker on the preceding comment line did not suppress"
  red   marker_absent "" "an ordinary comment above the line suppressed it — any comment now works as an exemption"
  green nonshell    "" "a non-shell file was scanned"
  green subtree     "" "a file in a tests/ subtree (never symlink-deployed) was scanned"

  # ── the ratchet must SHRINK: a grandfathered violation is green, a FIXED-but-still-listed file is
  #    red. Without the second half an allowlist is a permanent exemption list.
  green cd_parent "scripts/probe.sh"      "a grandfathered violation did not go GREEN"
  red   resolved  "scripts/probe.sh"      "a fixed-but-still-grandfathered file did not go RED (ratchet not shrinking)"

  # ── the REAL tree with the REAL allowlist. A stale ratchet is caught here too. Its two failure
  #    codes must stay APART: 1 is a VERDICT about the tree, 2 is a NON-VERDICT that says nothing
  #    whatever about the allowlist (memory: gate-never-ran-vs-gate-red).
  lint_tree "$ROOT" "$EMBEDDED_ALLOWLIST" >/dev/null 2>&1; rc_real=$?
  checks=$((checks + 1))
  case "$rc_real" in
    0) ;;
    2) echo "SELFTEST FAIL: could not scan $ROOT — a NON-VERDICT (bad ROOT?), NOT a stale allowlist"; fails=1 ;;
    *) echo "SELFTEST FAIL: the embedded allowlist is stale — the real tree is not clean"; fails=1 ;;
  esac

  # ── LOUD on an unusable scan tree, in both its forms.
  lint_tree "$d/nope" "" >/dev/null 2>&1; expect 2 "$?" "a missing scan root did not exit 2 (LOUD)"
  mkdir -p "$d/nolayers/docs"
  lint_tree "$d/nolayers" "" >/dev/null 2>&1; expect 2 "$?" "a root with NO deployed layers did not exit 2 (LOUD)"

  # ── OWN-SCOPE: both directions, because a scope that can only PASS is not a scope.
  lint_tree "$d/cd_parent" "" "scripts/other.sh" >/dev/null 2>&1; expect 0 "$?" "a violation OUTSIDE the own-set blocked (own-scope not applied)"
  lint_tree "$d/cd_parent" "" "scripts/probe.sh" >/dev/null 2>&1; expect 1 "$?" "a violation INSIDE the own-set did not block — own-scope disabled the rule"
  lint_tree "$d/resolved" "scripts/probe.sh" "scripts/other.sh" >/dev/null 2>&1; expect 0 "$?" "a stuck ratchet entry OUTSIDE the own-set blocked"
  lint_tree "$d/resolved" "scripts/probe.sh" "scripts/probe.sh" >/dev/null 2>&1; expect 1 "$?" "a stuck ratchet entry INSIDE the own-set did not block"
  # THE DOCS-ONLY CASE — an own-set SUPPLIED BUT EMPTY means "I change no file in these layers", so
  # nothing may block. The next two differ ONLY in arity, so together they prove the three states are
  # really distinguished and that `${3:-}` has not collapsed two of them.
  lint_tree "$d/cd_parent" "" "" >/dev/null 2>&1; expect 0 "$?" "an EMPTY own-set blocked — set-empty collapsed into unset, docs-only lands hard-stop"
  lint_tree "$d/cd_parent" "" >/dev/null 2>&1; expect 1 "$?" "an ABSENT own-set did not block — strict default lost"
  # entrypoint-level parity for the same distinction, via the real env seams.
  ( unset CC_SELFPATH_OWN; CC_SELFPATH_ALLOWLIST="" "$SELF" "$d/cd_parent" >/dev/null 2>&1 ); expect 1 "$?" "CC_SELFPATH_OWN unset did not block at the entrypoint"
  ( CC_SELFPATH_OWN="" CC_SELFPATH_ALLOWLIST="" "$SELF" "$d/cd_parent" >/dev/null 2>&1 ); expect 0 "$?" "CC_SELFPATH_OWN set-but-empty blocked at the entrypoint"

  # ── COULD-NOT-CHECK is a non-verdict, not a violation. Shadowing awk in a subshell reproduces
  #    what fork exhaustion (or another session's unscoped pkill) does to the detector. The contract
  #    is exit 2 and NO named finding — a killed check that names a file reads as an attributable RED
  #    and sends people to "fix" code that was never broken.
  ( awk() { return 2; }
    out="$(lint_tree "$d/cd_parent" "" 2>&1)"; rc=$?
    [ "$rc" -eq 2 ] || { echo "SELFTEST FAIL: an unrunnable detector did not exit 2 (got $rc) — a killed check must never be a verdict"; exit 1; }
    printf '%s' "$out" | grep -q 'SELF-PATH' && { echo "SELFTEST FAIL: an unrunnable detector still fabricated a SELF-PATH finding"; exit 1; }
    exit 0
  ); expect 0 "$?" "an unrunnable detector was treated as a verdict (see the message above)"
  # …and it stays a non-verdict WITH an own-set supplied: own-scope narrows which violations BLOCK,
  # it never makes an unrunnable check trustworthy. Guards the composition of the two mechanisms.
  ( awk() { return 2; }
    lint_tree "$d/cd_parent" "" "scripts/probe.sh" >/dev/null 2>&1
    [ "$?" -eq 2 ] || { echo "SELFTEST FAIL: an unrunnable detector under own-scope did not exit 2"; exit 1; }
    exit 0
  ); expect 0 "$?" "an unrunnable detector under own-scope was treated as a verdict"

  if [ "$fails" -eq 0 ]; then
    echo "self-path-lint --selftest: $checks/$checks — RED on all three real scar shapes (cd .., ROOT=, \$BASH_SOURCE), on an UNGUARDED root with unrelated \$HOME/.claude lines nearby, on a bare comment used as an exemption, and on a stuck ratchet entry; GREEN on a resolved \$0 doing the SAME '..' traversal, self re-exec, own-dir sibling, both tolerant-ladder spellings (continuation and if/elif/else), a next-line config fallback, prose, both escape-hatch placements, non-shell files, a tests/ subtree, and a grandfathered violation; GREEN on the real tree; LOUD on a missing root and on a root with no layers; own-scope blocks INSIDE / advises OUTSIDE for both violation kinds across all three arity states; NON-VERDICT on an unrunnable detector (with and without an own-set)."
    exit 0
  fi
  echo "self-path-lint --selftest: FAILED ($checks case(s) run) — the detector does not discriminate."
  exit 1
fi

# ── --print-scope: the population this lint JUDGES, as git pathspecs, one per line ────────────────
# LAYERS is the SAME variable lint_tree walks (:315), so the two cannot disagree: widening the
# deployed layers moves the scan and this answer in one edit. `<layer>/*` is EXACT rather than
# approximate — the walk is recursive under each layer, and a git pathspec's `*` matches `/` unless
# `:(glob)` magic is asked for, so the two cover the same file set.
#
# WHY IT EXISTS (backlog 5fc8ff411a7c, extending 0be0bd2c0b65 to the six arms that were left out of
# it). scripts/ship-land.sh built this lint's own-scope set — the files allowed to BLOCK a land —
# from a `-- 'bin/*' 'hooks/*' 'scripts/*'` pathspec RESTATED in ship-land. Unlike the two arms
# 0be0bd2c0b65 closed, that restatement could not drift at RUNTIME (this lint has no env seam on its
# population), and that was the whole of its defence: it could still drift by a CODE edit to LAYERS,
# with the same silent failure direction — an own-set that MISSES a file does not error, it is the
# legitimate spelling of "this land touches nothing I judge", so the finding degrades to advisory
# and the land proceeds (memory: resident-policy-must-not-restate-perishable-facts).
#
# EXIT 0 WITH A NON-EMPTY LIST IS THE ONLY SUCCESS. A lint that cannot answer — missing, or an older
# copy that reads the flag as a scan root and exits 2 — yields an empty answer, and ship-land's
# lint_own_scope turns that into a NON-VERDICT (rc 2 ⇒ GATE_KILLED ⇒ retryable), never into an empty
# own-set. Those are different answers: empty-with-rc-0 legitimately means "your land touches nothing
# I judge", and collapsing them reinstates the silent-advisory defect by a new route.
if [ "${1:-}" = "--print-scope" ]; then
  _ps_restore_f=0; case "$-" in *f*) _ps_restore_f=1 ;; esac
  # Globbing OFF for the split: an unquoted expansion would also PATHNAME-EXPAND each layer against
  # the caller's CWD and print real repo paths instead of the pathspec.
  set -f
  for _ps_l in $LAYERS; do printf '%s/*\n' "$_ps_l"; done
  [ "$_ps_restore_f" -eq 1 ] || set +f
  exit 0
fi

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  # The header block, DERIVED rather than a hardcoded line range: every edit to the header would
  # otherwise silently truncate --help mid-sentence (this one had already lost the exit codes, the
  # env seams and the three exemption tiers before anyone read it back).
  awk 'NR > 1 { if ($0 !~ /^#/) exit; if ($0 ~ /^# *shellcheck /) next; sub(/^# ?/, ""); print }' "$SELF"
  exit 0
fi

# CC_SELFPATH_OWN — newline-delimited repo-relative paths the caller is answerable for. UNSET ⇒
# strict whole-tree blocking. SET (including set to EMPTY) ⇒ own-scope, where empty legitimately
# means "I change no file in these layers, so nothing may block me". `+set` is the only test that
# separates those; `${CC_SELFPATH_OWN:-}` would collapse them and silently reinstate the hard stop
# for precisely the docs-only land that motivates own-scope.
if [ -n "${CC_SELFPATH_OWN+set}" ]; then
  lint_tree "${1:-$ROOT}" "${CC_SELFPATH_ALLOWLIST-$EMBEDDED_ALLOWLIST}" "$CC_SELFPATH_OWN"
else
  lint_tree "${1:-$ROOT}" "${CC_SELFPATH_ALLOWLIST-$EMBEDDED_ALLOWLIST}"
fi
exit $?
