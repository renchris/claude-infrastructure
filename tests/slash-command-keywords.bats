#!/usr/bin/env bats
# The slash-menu KEYWORDS a command promises to answer to.
#
# WHY A TEST AND NOT A COMMENT: the autocomplete match is not on the command's name alone. Read out
# of the binary (class GVt, identical in 2.1.219 / 2.1.220 / 2.1.260) the menu is a Fuse.js index
# with keys commandName(3) displayName(2) partKey(2) aliasKey(2) displayPartKey(1) and
# descriptionKey(0.5) at threshold 0.3 — and `descriptionKey` is built as
#   description.split(" ").map(w => w.toLowerCase().replace(/[^a-z0-9]/g, "")).filter(Boolean)
# so it indexes WHOLE SPACE-SEPARATED TOKENS. Two consequences the eye does not catch in review:
#   1. a hyphenated phrase indexes as one token — "lid-close" is "lidclose", and does NOT answer /lid;
#   2. with no frontmatter, a command's description DEFAULTS TO THE FILE'S FIRST LINE, so a keyword
#      that sits on line 2 is not indexed at all. That is exactly how /keep-laptop-alive answered
#      "lid" (line 1) but not "sleep" ("suspended mid-turn", line 2) until 2026-09-13.
# `aliases` is not a supported key for a file-based command, so the description is the only lever.
#
# NOT PINNED HERE, deliberately: the prose contract inside a command body (e.g. "empty $ARGUMENTS
# means toggle"). Its only test surface is grep-for-a-phrase, which fires on harmless rewording and
# still cannot see whether the model obeyed — a brittle test bought with no verdict.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # Hermetic by construction: these cases read only $REPO, but the partition lint requires every
  # suite to fixture HOME so no case can ever reach the operator's live ~/ by accident.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
}

# Tokenize a description exactly as the binary's descriptionKey builder does.
tokens() { tr ' ' '\n' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g' | grep -v '^$'; }

# The frontmatter description, or empty when the file declares none.
fm_description() {
  awk 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} /^description:/{sub(/^description:[[:space:]]*/,""); print; exit}' "$1"
}

@test "keep-laptop-alive declares its description in frontmatter, not by accident of line 1" {
  run fm_description "$REPO/commands/keep-laptop-alive.md"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "keep-laptop-alive answers /lid and /sleep in the slash menu" {
  local desc; desc="$(fm_description "$REPO/commands/keep-laptop-alive.md")"
  local toks; toks="$(printf '%s' "$desc" | tokens)"
  for kw in lid sleep; do
    if ! printf '%s\n' "$toks" | grep -qx "$kw"; then
      printf 'keyword %q is not a standalone token of the description:\n  %s\n' "$kw" "$desc" >&2
      return 1
    fi
  done
}
