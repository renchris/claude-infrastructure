#!/bin/sh
# docs/ refresh queue: which curated pages are stale against docs/mirror/.
# Run from the repo root.  DEPENDS.tsv column 2 is REPO-RELATIVE (docs/mirror/...).
# rc 0 = every row fresh · 1 = rows need action (printed) · 2 = DEPENDS.tsv unusable.
TSV=${1:-docs/DEPENDS.tsv}
OUT=$(awk -F'\t' '
  NR==1 && $1!="page" { print "DEPENDS.tsv: missing header row (page/source/pinned_sha/role)" >"/dev/stderr"; exit 2 }
  NR==1 { next }
  NF < 3 { printf "MALFORMED\t%s\t(fields=%d)\n", $1, NF; n++; next }
  {
    page=$1; src=$2; pin=$3; cur=""; st=""; ok=0; dash=0
    if (pin == "")         { printf "UNPINNED\t%s\t%s\n", page, src; n++; next }
    if (pin !~ /^[0-9a-f]{64}$/) { printf "BAD-PIN\t%s\t%s\t(len=%d)\n", page, src, length(pin); n++; next }
    while ((getline line < src) > 0) {
      if (line == "---") { if (++dash == 2) break; else continue }
      if (line ~ /^rendered_sha256: /) { cur=substr(line, 18); ok=1 }
      else if (line ~ /^status: /)     { st =substr(line, 9) }
    }
    close(src)
    if (!ok && st == "deleted") { printf "SOURCE-DELETED\t%s\t%s\n", page, src; n++; next }
    if (!ok)                    { printf "MISSING-OR-UNPARSEABLE\t%s\t%s\n", page, src; n++; next }
    if (cur != pin)             { printf "STALE\t%s\t%s\n", page, src; n++; next }
  }
  END { exit (n>0) }
' "$TSV" | sort -u) || true
awk -F'\t' 'NR==1 && $1!="page"{exit 2} {next}' "$TSV" || exit 2
[ -n "$OUT" ] && { printf '%s\n' "$OUT"; exit 1; }
exit 0
