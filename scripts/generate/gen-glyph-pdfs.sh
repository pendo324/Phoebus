#!/usr/bin/env bash
# Converts the kit icons in Sources/PhoebusUI/Resources/Glyphs/source/*.svg
# into the vector PDFs StockIcon draws. The SVGs are the kits' files with
# their stroke width set, the colour made black and the viewBox cropped to
# the ink; see Resources/Glyphs/LICENSES.md for where each one comes from.
set -euo pipefail
cd "$(dirname "$0")/../../Sources/PhoebusUI/Resources/Glyphs"
for svg in source/*.svg; do
    name=$(basename "$svg" .svg)
    SOURCE_DATE_EPOCH=0 rsvg-convert -f pdf -o "$name.pdf" "$svg"
done
