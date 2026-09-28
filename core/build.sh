#!/bin/bash
# build.sh — embed core/ into install-core.sh, so the installer is one self-contained file.
#
#   core/build.sh           rewrite the EMBEDDED CORE region of install-core.sh
#   core/build.sh --check   exit 1 if the region is out of date (tests/install-core.bats)
#
# Each core file becomes a quoted heredoc (no expansion, byte-exact), so the published installer's
# sha256 pins every file it installs. VERSION is a checksum of the embedded sources.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALLER="$ROOT/install-core.sh"
EOF_MARK="__AUTONOMY_CORE_EOF__"
# <path under core/> <mode> — the installer copies exactly these.
FILES="hooks/lib.sh:755 hooks/continue.sh:755 hooks/completion-gate.sh:755 hooks/backup-before-write.sh:755
bin/autonomy:755 CLAUDE.core.md:644 commands/wrap.md:644 commands/handoff.md:644"

region() {
  local entry path mode sum=""
  for entry in $FILES; do
    path="${entry%:*}"
    [ -f "$ROOT/core/$path" ] || { echo "core/build.sh: missing core/$path" >&2; exit 1; }
    if grep -q "$EOF_MARK" "$ROOT/core/$path"; then
      echo "core/build.sh: core/$path contains the heredoc marker $EOF_MARK" >&2; exit 1
    fi
    [ -z "$(tail -c1 "$ROOT/core/$path")" ] || { echo "core/build.sh: core/$path must end with a newline" >&2; exit 1; }
    sum="$sum$(cksum < "$ROOT/core/$path")"
  done
  echo "# >>> BEGIN EMBEDDED CORE"
  echo "ac_emit 'VERSION' 644 <<'$EOF_MARK'"
  echo "core-$(printf '%s' "$sum" | cksum | awk '{print $1}')"
  echo "$EOF_MARK"
  for entry in $FILES; do
    path="${entry%:*}"; mode="${entry##*:}"
    echo "ac_emit '$path' $mode <<'$EOF_MARK'"
    cat "$ROOT/core/$path"
    echo "$EOF_MARK"
  done
  echo "# <<< END EMBEDDED CORE"
}

build() {  # → the whole installer with a fresh region, on stdout
  local reg
  reg="$(mktemp)"
  region > "$reg"
  awk -v reg="$reg" '
    /^# >>> BEGIN EMBEDDED CORE$/ { while ((getline l < reg) > 0) print l; skip=1; next }
    /^# <<< END EMBEDDED CORE$/   { skip=0; next }
    !skip' "$INSTALLER"
  rm -f "$reg"
}

new="$(mktemp)"
trap 'rm -f "$new"' EXIT
build > "$new"
if [ "${1:-}" = --check ]; then
  if cmp -s "$new" "$INSTALLER"; then echo "install-core.sh is up to date with core/"; exit 0; fi
  echo "install-core.sh is STALE: run core/build.sh" >&2
  diff "$INSTALLER" "$new" | head -20 >&2 || true
  exit 1
fi
cmp -s "$new" "$INSTALLER" && { echo "install-core.sh already up to date"; exit 0; }
cat "$new" > "$INSTALLER"
bash -n "$INSTALLER"
echo "install-core.sh rebuilt ($(grep -c "^ac_emit " "$INSTALLER") files embedded)"
