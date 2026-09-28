#!/usr/bin/env bash
# setup.sh <setup-spec> <fixture-dir> <run-dir> — plant one #35 task's fixture state.
#
# A spec is `-` (nothing), `rmmem:<file>` (delete a topic file and its index line from the run's
# frozen store copy, so an UNINDEXED twin is the only prior copy of the rule), or `plant:<name>`
# (write the files below into the fixture, commit them, then apply any post-commit state).
# Every planted script prints its symptom through a FOREIGN emitter (git, bash, shellcheck), never
# through our own text, which is the #6 seed rule (hooks/lib/lesson-symptoms.tsv header).
set -u
SPEC=${1:?spec}; FX=${2:?fixture}; RUN=${3:?run dir}
MEM="$RUN/mem"

commit_planted() {
  git -C "$FX" add -A && git -C "$FX" commit -q -m "ops: planted fixture" && git -C "$FX" push -q origin HEAD:main
}

case "$SPEC" in
  -) exit 0 ;;
  rmmem:*)
    f=${SPEC#rmmem:}
    # The one delete in the harness: a single named file inside THIS run's own store copy.
    case "$f" in */*|..*|'') echo "setup: bad rmmem name $f" >&2; exit 2 ;; esac
    real=$(cd "$MEM" && pwd -P); runreal=$(cd "$RUN" && pwd -P)
    case "$real/" in "$runreal"/*) ;; *) echo "setup: $MEM is not under $RUN" >&2; exit 2 ;; esac
    rm -f "$real/$f"
    grep -vF "($f)" "$real/MEMORY.md" > "$real/MEMORY.md.n" && mv "$real/MEMORY.md.n" "$real/MEMORY.md"
    exit 0 ;;
  plant:*) ;;
  *) echo "setup: unknown spec $SPEC" >&2; exit 2 ;;
esac

mkdir -p "$FX/ops"
case "${SPEC#plant:}" in
  check-landed)
    git -C "$FX" rev-parse 'HEAD^{tree}' > "$FX/RELEASE_REF"
    cat > "$FX/ops/check-landed.sh" <<'EOF'
#!/usr/bin/env bash
# check-landed.sh — has the release ref (RELEASE_REF) landed on main?
ref=$(cat "$(dirname "$0")/../RELEASE_REF")
git merge-base --is-ancestor "$ref" main
rc=$?
if [ "$rc" -eq 0 ]; then echo "LANDED"; else echo "NOT LANDED"; fi
EOF
    commit_planted ;;
  nightly)
    cat > "$FX/ops/nightly.sh" <<'EOF'
#!/usr/bin/env bash
# nightly.sh — print the non-skipped stages of tonight's run.
for stage in fetch skip report; do
  out=$(case "$stage" in skip) continue ;; *) echo "stage: $stage" ;; esac)
  [ -n "$out" ] && echo "$out"
done
echo "nightly: done"
EOF
    cat > "$FX/ops/com.example.nightly.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.example.nightly</string>
  <key>ProgramArguments</key>
  <array><string>/usr/bin/env</string><string>bash</string><string>$FX/ops/nightly.sh</string></array>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
  <key>StartCalendarInterval</key><dict><key>Hour</key><integer>3</integer></dict>
</dict>
</plist>
EOF
    commit_planted ;;
  gate)
    cat > "$FX/ops/gate.sh" <<'EOF'
#!/usr/bin/env bash
# gate.sh — the land gate's lint leg: every ops/*.sh must be clean under the gate's shellcheck.
rc=0
for f in "$(dirname "$0")"/*.sh; do
  shellcheck "$f" || rc=1
done
if [ "$rc" -eq 0 ]; then echo "gate: PASS"; else echo "gate: REFUSED"; fi
exit "$rc"
EOF
    # shellcheck disable=SC2016  # literal script text for the fixture, expanded when IT runs
    printf '%s\n' '#!/usr/bin/env bash' 'greet() { printf "hi %s\n" "$1"; }' > "$FX/ops/lib.sh"
    # shellcheck disable=SC2016  # literal script text for the fixture, expanded when IT runs
    printf '%s\n' '#!/usr/bin/env bash' '. "$(dirname "$0")/lib.sh"' 'greet "$1"' > "$FX/ops/uses-lib.sh"
    commit_planted ;;
  land)
    cat > "$FX/ops/land.sh" <<'EOF'
#!/usr/bin/env bash
# land.sh — rebase this checkout onto origin/main and push it.
git fetch -q origin || exit 1
if ! git rebase origin/main; then echo "land: FAILED"; exit 1; fi
git push -q origin HEAD:main && echo "land: LANDED"
EOF
    printf 'Release notes\n\nTeh first line.\n' > "$FX/notes.md"
    commit_planted
    printf 'local feature\n' > "$FX/ops/feature.txt"
    git -C "$FX" add ops/feature.txt && git -C "$FX" commit -q -m "feat: local feature"
    git clone -q "$RUN/origin.git" "$RUN/other" && git -C "$RUN/other" config user.email o@example.invalid \
      && git -C "$RUN/other" config user.name Other && printf 'upstream\n' > "$RUN/other/UPSTREAM" \
      && git -C "$RUN/other" add UPSTREAM && git -C "$RUN/other" commit -q -m "upstream change" \
      && git -C "$RUN/other" push -q origin HEAD:main || exit 3
    printf 'Release notes\n\nThe first line.\n' > "$FX/notes.md" ;;
  *) echo "setup: unknown plant ${SPEC#plant:}" >&2; exit 2 ;;
esac
