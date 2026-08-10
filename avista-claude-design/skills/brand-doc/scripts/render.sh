#!/usr/bin/env bash
#
# render.sh — render a self-contained HTML document to a print-ready PDF via headless Chrome,
#             then verify that the content and the design system's webfont actually made it in.
#
# Usage:   render.sh <input.html> <output.pdf> [virtual-time-budget-ms]
# Example: render.sh report.html production-notes/RMK-Performance-Audit-2026-08-10.pdf
#
# Why Chrome and not a PDF library: Chrome resolves the design system's @import, downloads the
# Google Font and embeds a subset. reportlab/WeasyPrint silently fall back to a default face, which
# produces a PDF that renders without error but is not the brand.
#
# Env overrides:
#   CHROME_BIN   full path to a Chrome/Chromium binary, checked before the built-in candidates
#   PAPER        unused by Chrome directly; set @page size in the HTML instead (see render-notes.md)

set -euo pipefail

die() { printf 'render.sh: %s\n' "$1" >&2; exit 1; }

[ $# -ge 2 ] || die "usage: render.sh <input.html> <output.pdf> [virtual-time-budget-ms]"

INPUT=$1
OUTPUT=$2
BUDGET=${3:-4000}

[ -f "$INPUT" ] || die "input not found: $INPUT"

# Chrome needs an absolute file:// URL — a relative path renders a blank PDF with no error.
ABS_INPUT=$(cd "$(dirname "$INPUT")" && printf '%s/%s' "$(pwd)" "$(basename "$INPUT")")

OUT_DIR=$(dirname "$OUTPUT")
[ -d "$OUT_DIR" ] || die "output directory does not exist: $OUT_DIR"
ABS_OUTPUT=$(cd "$OUT_DIR" && printf '%s/%s' "$(pwd)" "$(basename "$OUTPUT")")

# ---------------------------------------------------------------------------
# Locate a Chromium-family browser
# ---------------------------------------------------------------------------
CHROME=""
CANDIDATES=(
  "${CHROME_BIN:-}"
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  "/Applications/Chromium.app/Contents/MacOS/Chromium"
  "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"
  "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"
)
for candidate in "${CANDIDATES[@]}"; do
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then CHROME=$candidate; break; fi
done
if [ -z "$CHROME" ]; then
  for name in google-chrome chromium chromium-browser microsoft-edge brave-browser; do
    if command -v "$name" >/dev/null 2>&1; then CHROME=$(command -v "$name"); break; fi
  done
fi
[ -n "$CHROME" ] || die "no Chrome/Chromium binary found. Set CHROME_BIN, or deliver the styled HTML instead — do not substitute a PDF library, the fonts will not match."

printf 'Rendering with: %s\n' "$CHROME"

# ---------------------------------------------------------------------------
# Render
#   --virtual-time-budget lets the webfont finish loading before the print snapshot.
#   --no-pdf-header-footer strips Chrome's default URL/date furniture.
# ---------------------------------------------------------------------------
"$CHROME" \
  --headless \
  --disable-gpu \
  --no-sandbox \
  --no-pdf-header-footer \
  --virtual-time-budget="$BUDGET" \
  --run-all-compositor-stages-before-draw \
  --print-to-pdf="$ABS_OUTPUT" \
  "file://$ABS_INPUT" 2>/dev/null

[ -f "$ABS_OUTPUT" ] || die "Chrome produced no output file"

SIZE=$(wc -c < "$ABS_OUTPUT" | tr -d ' ')
printf 'Wrote: %s (%s bytes)\n' "$ABS_OUTPUT" "$SIZE"

# ---------------------------------------------------------------------------
# Verify — two silent failure modes, two cheap checks
# ---------------------------------------------------------------------------
STATUS=0

# 1. Did the content survive? Empty text means a failed render or content clipped past the page box.
if command -v pdftotext >/dev/null 2>&1; then
  CHARS=$(pdftotext "$ABS_OUTPUT" - 2>/dev/null | tr -d '[:space:]' | wc -c | tr -d ' ')
  if [ "$CHARS" -lt 20 ]; then
    printf '  FAIL  text layer is essentially empty (%s chars) — check the file:// path and page box\n' "$CHARS"
    STATUS=1
  else
    printf '  ok    text layer present (%s chars)\n' "$CHARS"
  fi
else
  printf '  skip  pdftotext not installed — read the PDF directly to confirm content\n'
fi

# 2. Did the design system's font embed, or did Chrome fall back? This is the failure that looks
#    correct in a file listing and wrong to anyone who knows the brand.
if command -v pdffonts >/dev/null 2>&1; then
  FONTS=$(pdffonts "$ABS_OUTPUT" 2>/dev/null | tail -n +3)
  EMBEDDED=$(printf '%s\n' "$FONTS" | awk '$0 != "" && $(NF-4) == "yes"' | wc -l | tr -d ' ')
  if [ "$EMBEDDED" -gt 0 ]; then
    printf '  ok    %s embedded font(s):\n' "$EMBEDDED"
    printf '%s\n' "$FONTS" | awk '$0 != ""{printf "          %s\n", $1}'
  else
    printf '  WARN  no embedded fonts — the webfont did not load, so this is NOT branded type.\n'
    printf '        Raise the virtual-time-budget (arg 3, try 8000), confirm the @import is the\n'
    printf '        first rule in the stylesheet, and check network access.\n'
    STATUS=1
  fi
else
  printf '  skip  pdffonts not installed (brew install poppler) — cannot confirm font embedding\n'
fi

exit $STATUS
