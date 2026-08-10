#!/usr/bin/env bash
# render.sh — turn a .pptx into one PNG per slide so an agent can LOOK at its own work.
#
#   ./render.sh deck.pptx [outdir] [dpi]
#
# Route: LibreOffice headless -> PDF -> pdftoppm -> slide-NN.png
# LibreOffice is used because it is the only headless renderer on macOS that needs no
# Automation consent prompt and no GUI session. Its fidelity caveats are documented in
# references/verification.md -- read them before calling a discrepancy a defect.
#
# bash 3.2 compatible (macOS ships 3.2; do not use mapfile or associative arrays).

set -euo pipefail

PPTX="${1:?usage: render.sh <deck.pptx> [outdir] [dpi]}"
OUTDIR="${2:-$(dirname "$PPTX")/render}"
DPI="${3:-110}"

SOFFICE=""
for cand in \
  "/Applications/LibreOffice.app/Contents/MacOS/soffice" \
  "$(command -v soffice 2>/dev/null || true)" \
  "$(command -v libreoffice 2>/dev/null || true)"
do
  if [ -n "$cand" ] && [ -x "$cand" ]; then SOFFICE="$cand"; break; fi
done

if [ -z "$SOFFICE" ]; then
  echo "render.sh: LibreOffice not found." >&2
  echo "  install: brew install --cask libreoffice" >&2
  exit 2
fi

if ! command -v pdftoppm >/dev/null 2>&1; then
  echo "render.sh: pdftoppm not found (part of poppler)." >&2
  echo "  install: brew install poppler" >&2
  exit 2
fi

[ -f "$PPTX" ] || { echo "render.sh: no such file: $PPTX" >&2; exit 2; }

mkdir -p "$OUTDIR"
rm -f "$OUTDIR"/slide-*.png "$OUTDIR"/*.pdf

# LibreOffice needs a writable, private profile or concurrent runs collide.
PROFILE="$(mktemp -d "${TMPDIR:-/tmp}/lo-profile.XXXXXX")"
trap 'rm -rf "$PROFILE"' EXIT

"$SOFFICE" \
  --headless --norestore --nolockcheck --nodefault --nofirststartwizard \
  -env:UserInstallation="file://$PROFILE" \
  --convert-to pdf --outdir "$OUTDIR" "$PPTX" >/dev/null 2>&1

BASE="$(basename "$PPTX")"
PDF="$OUTDIR/${BASE%.*}.pdf"

[ -f "$PDF" ] || { echo "render.sh: conversion produced no PDF for $PPTX" >&2; exit 1; }

pdftoppm -png -r "$DPI" "$PDF" "$OUTDIR/slide"

COUNT=$(ls -1 "$OUTDIR"/slide-*.png 2>/dev/null | wc -l | tr -d ' ')
echo "render.sh: $COUNT slide(s) -> $OUTDIR/slide-NN.png @ ${DPI}dpi"
[ "$COUNT" -gt 0 ] || exit 1
