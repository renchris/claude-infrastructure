#!/usr/bin/env bash
# Regenerate every brief in briefs/ from manifest.json.
#
# The brief body is the artifact EXTRACTED BYTE-FOR-BYTE from git at the record's
# pre_fix_ref — never a hand-edited stand-in. That is control 2 of the three the
# corpus rests on (a hand-reconstructed "buggy-looking" file passes vacuously,
# because reconstruction drops exactly the incidental detail that made the defect
# survive a first look).
#
# The preamble is a single constant, so every brief is word-identical apart from
# the opaque id and the subject path — the two things an arm may see. Nothing in a
# brief names the defect, the commit, the date, or the repo's own history.
#
# Usage:  bash tests/fixtures/codex-probe/build-briefs.sh
# Check:  bash tests/fixtures/codex-probe/verify-corpus.sh
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel)"
MANIFEST="$HERE/manifest.json"
# CODEX_PROBE_OUT lets a checker regenerate into a scratch dir and diff, rather than
# overwriting the committed briefs to find out whether they would have changed.
OUT="${CODEX_PROBE_OUT:-$HERE/briefs}"
mkdir -p "$OUT"

# ── the instruction block handed to every arm, identical for defect and clean briefs ──
emit_preamble() {
	local subject="$1"
	cat <<PREAMBLE
# Review brief $2

You are reviewing one file taken from a working software repository. It is real code
that was in production use.

Read the file below in full and report every defect you find.

A **defect** is anything that makes the code do something other than what it is for:
a wrong result, a check that is silently skipped, a guard that does not cover the
class it claims to cover, an assertion that passes or fails for the wrong reason, an
action taken on an unproven premise, or a failure reported as a success. Style,
formatting, naming, and performance are out of scope.

This file may or may not contain defects. Report only what you can point at in the
code. If you find none, say so plainly.

For each defect, report exactly three things:

1. **What** — one sentence stating the defect.
2. **Where** — the line number(s), and the exact line of code, copied verbatim.
3. **Why it is wrong** — the input or condition under which the code does the wrong
   thing, and what happens then.

Do not propose fixes. Do not use any tool, file, or resource other than the text of
this brief.

## File under review — \`$subject\`

PREAMBLE
}

count=0
while IFS=$'\t' read -r id subject ref; do
	[ -n "$id" ] || continue
	dest="$OUT/$id.md"
	{
		emit_preamble "$subject" "$id"
		printf '```bash\n'
		git -C "$REPO" show "$ref:$subject"
		printf '```\n'
	} >"$dest"
	printf 'wrote %-28s %s:%s\n' "$dest" "${ref:0:12}" "$subject"
	count=$((count + 1))
done < <(python3 -c '
import json, sys
for b in json.load(open(sys.argv[1])):
    print("\t".join([b["id"], b["subject_path"], b["pre_fix_ref"]]))
' "$MANIFEST")

echo "built $count briefs"
