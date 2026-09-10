#!/bin/bash
# bash32-parse-lint — a RATCHET asserting every shipped shell script still PARSES under bash 3.2.
#
# WHY THIS EXISTS, and it is in-tree history rather than a hypothesis. macOS ships bash **3.2.57** at
# /bin/bash and has since 2007 (bash 4+ is GPLv3, which Apple does not ship). Both this box and the
# GitHub `macos-*` runner therefore resolve a BARE `bash` to 3.2 whenever the PATH does not put a
# brew bash first. The operator's interactive PATH does put brew bash 5.3 first — so a construct that
# bash 3.2 cannot PARSE is invisible on the desk and fatal off-box.
#
# THE SCAR: scripts/mcp-ssot-wire.sh carried, inside a `<<'PY'` heredoc nested in a `$( )` command
# substitution, the comment `# Merge: set only the SSOT's own keys.` Bash 3.2 does NOT recognise a
# heredoc delimiter inside `$( )` — it lexes the heredoc BODY as shell code — so that lone apostrophe
# opened an unterminated single-quoted string and the whole file died at parse time:
#     /bin/bash: line 288: syntax error near unexpected token `fi'
# The script then exited 2 before doing anything, and every test case that ran it failed while the
# two cases that only read JSON passed. Measured off-box signature, reproduced EXACTLY on this box
# with `bash` pinned to 3.2: tests/mcp-ssot-wire.bats 2 ok / 10 not ok, tests/mcp-no-inherit.bats
# 20 ok / 1 not ok. Both suites were red in **12 of 12** clean post-cure scheduled folds — the
# deterministic floor that made a green off-box verdict structurally unreachable, since every fold
# contained at least one of them. Evidence: docs/research/offbox-deterministic-floor-2026-09-10.md.
#
# WHY A PARSE RATCHET AND NOT AN APOSTROPHE BAN. Banning apostrophes in heredocs would enumerate one
# SPELLING of the class (memory: denylist-enumerates-spellings-not-the-class). `bash -n` under the
# real 3.2 binary tests the PROPERTY — it catches every 3.2 incompatibility, including the ones
# nobody has met yet, and it cannot drift from what the runner actually does because it IS what the
# runner actually does.
#
# POPULATION: tracked files whose shebang names bash or sh — i.e. exactly the files something can
# invoke as `bash <file>`. `.bats` files are EXCLUDED: bats parses them with the bash IT resolves,
# never with a bare `bash`, so scanning them would flag fixtures that are never executed as scripts.
#
# THE INSTRUMENT IS CONTROLLED. A script is reported ONLY when it fails under 3.2 AND parses clean
# under a modern bash. That differential is what separates "3.2 cannot parse this" from "this file is
# simply broken" — a plain syntax error is some other lint's finding, not this one's, and reporting
# it here would let this ratchet take credit for a defect it did not discriminate.
#
# Exit: 0 = every script parses under 3.2 · 1 = at least one 3.2-only parse failure
#       2 = unusable environment (no bash 3.x at /bin/bash, or no modern bash for the control arm).
#           Exit 2 is deliberately NOT 0: a fail-safe default that matched the healthy output would
#           be unfalsifiable (memory: fail-safe-default-mimics-the-healthy-state).

set -uo pipefail

OLD_BASH="${CC_BASH32:-/bin/bash}"
usage() { echo "usage: bash32-parse-lint.sh [FILE...]   (no args = every tracked file)" >&2; exit 2; }

# Shebang test in pure shell: `grep` is PATH-resolved on this box (ugrep interactively, BSD grep in
# a hook) and \b is not portable across them, so the population must not depend on which one wins.
_is_shell_script() {
  # A .bats file is EXCLUDED BY EXTENSION, not by its shebang. Every suite in this tree carries
  # `#!/usr/bin/env bats` today and would fall through the shebang test anyway — keying on the
  # shebang would make the exclusion dead code a mutant could delete with the suite staying green.
  # The extension is the durable statement of the population: bats parses these with the bash IT
  # resolves, never via a bare `bash`, so their syntax is not this ratchet's business.
  case "$1" in *.bats) return 1 ;; esac
  # `tr -d '\0'` first: a binary tracked file otherwise makes the command substitution warn
  # about ignored null bytes, once per file, drowning the verdict.
  local first; first="$(LC_ALL=C head -1 "$1" 2>/dev/null | LC_ALL=C tr -d '\0')"
  case "$first" in
    '#!'*bash*) return 0 ;;
    '#!'*/sh|'#!'*/sh\ *|'#!'*[!a-z]sh|'#!'*[!a-z]sh\ *) return 0 ;;
    *) return 1 ;;
  esac
}

_find_new_bash() {
  local c
  for c in /opt/homebrew/bin/bash /usr/local/bin/bash "$(command -v bash 2>/dev/null)"; do
    [ -n "$c" ] && [ -x "$c" ] || continue
    # shellcheck disable=SC2016  # single quotes are the point: the CHILD bash expands this, not us
    case "$("$c" -c 'echo ${BASH_VERSINFO[0]}' 2>/dev/null) " in [4-9]*|[1-9][0-9]*) echo "$c"; return 0 ;; esac
  done
  return 1
}

main() {
  local -a explicit=()
  while [ $# -gt 0 ]; do
    case "$1" in -h|--help) usage ;; -*) usage ;; *) explicit+=("$1") ;; esac; shift
  done
  if [ "${#explicit[@]}" -eq 0 ]; then
    local root; root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git repo" >&2; exit 2; }
    cd "$root" || exit 2
  fi

  [ -x "$OLD_BASH" ] || { echo "bash32-parse-lint: no executable at $OLD_BASH — NON-VERDICT" >&2; exit 2; }
  local ov
  # shellcheck disable=SC2016  # the child bash must expand BASH_VERSINFO, not this one
  ov="$("$OLD_BASH" -c 'echo ${BASH_VERSINFO[0]}' 2>/dev/null)"
  [ "$ov" = "3" ] || { echo "bash32-parse-lint: $OLD_BASH is bash $ov, not 3.x — NON-VERDICT" >&2; exit 2; }
  local NEW_BASH; NEW_BASH="$(_find_new_bash)" || {
    echo "bash32-parse-lint: no modern bash for the control arm — NON-VERDICT" >&2; exit 2; }

  local rc=0 scanned=0 f
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    _is_shell_script "$f" || continue
    scanned=$((scanned+1))
    "$OLD_BASH" -n "$f" 2>/dev/null && continue
    # control arm: only a 3.2-ONLY failure is this ratchet's finding
    "$NEW_BASH" -n "$f" 2>/dev/null || continue
    rc=1
    # shellcheck disable=SC2016  # ditto: $BASH_VERSION is the child's, not ours
    echo "  ✗ $f — parses under $("$NEW_BASH" -c 'echo $BASH_VERSION') but NOT under bash $ov:" >&2
    "$OLD_BASH" -n "$f" 2>&1 | head -2 | sed 's/^/      /' >&2
  done < <(if [ "${#explicit[@]}" -gt 0 ]; then printf '%s\n' "${explicit[@]}"; else git ls-files; fi)

  if [ "$rc" -eq 0 ]; then
    echo "bash32-parse-lint: $scanned script(s) parse under bash $ov — clean"
  else
    echo "bash32-parse-lint: 3.2-only parse failure(s) above. macOS /bin/bash is 3.2 and the" >&2
    echo "  off-box runner uses it, so this file is DEAD there while green on the desk." >&2
  fi
  return $rc
}

main "$@"
