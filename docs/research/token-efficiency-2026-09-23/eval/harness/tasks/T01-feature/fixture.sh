#!/bin/bash
# fixture.sh <fixture-dir> <origin-bare-dir>  (ported from the 2026-09-23 pilot)
set -euo pipefail
FX=$1; R=$2
rm -rf "$FX" "$R"; mkdir -p "$FX"
git init -q -b main "$FX"
git -C "${FX:?fixture path required}" config user.name "Eval Fixture"
git -C "${FX:?fixture path required}" config user.email "fixture@example.invalid"
cat > "$FX/count.sh" <<'SH'
#!/bin/bash
# count.sh [dir] — print the total number of lines across all .txt files in dir (default: .)
dir="${1:-.}"
total=0
for f in "$dir"/*.txt; do
  [ -e "$f" ] || continue
  n=$(wc -l < "$f")
  total=$((total + n))
done
echo "$total"
SH
chmod +x "$FX/count.sh"
printf 'alpha\nbeta\ngamma\n' > "$FX/a.txt"
printf 'one\ntwo\nthree\nfour\nfive\n' > "$FX/b.txt"
printf '# counter\n\n`./count.sh [dir]` prints the total line count of the `.txt` files in `dir` (default: current directory).\n' > "$FX/README.md"
git -C "$FX" add -A
git -C "$FX" commit -q -m "chore: initial"
git init -q --bare "$R"
git -C "$FX" remote add origin "$R"
git -C "$FX" push -q -u origin main
