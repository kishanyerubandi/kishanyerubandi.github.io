#!/usr/bin/env bash
# One command: compile both TikZ optical sizes plus transparent Safari mask,
# and generate a complete multi-platform favicon set.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRCDIR="$ROOT/favicon-src"
IMG="$ROOT/assets/img"
mkdir -p "$IMG"
for cmd in pdflatex pdftocairo python3; do
  command -v "$cmd" >/dev/null || { echo "Missing $cmd" >&2; exit 1; }
done
if command -v magick >/dev/null; then IM=(magick)
elif command -v convert >/dev/null; then IM=(convert)
else echo "Install imagemagick" >&2; exit 1; fi

# Read the colors from the one shared LaTeX color palette.
get_color() {
  sed -nE "s/^[[:space:]]*\\\\definecolor\\{$1\\}\\{HTML\\}\\{([[:xdigit:]]{6})\\}.*/\\1/p" "$SRCDIR/palette.tex" | head -n1
}
BGHEX="$(get_color BackgroundColor)"
PINHEX="$(get_color SafariPinColor)"
[[ "$BGHEX" =~ ^[[:xdigit:]]{6}$ && "$PINHEX" =~ ^[[:xdigit:]]{6}$ ]] || {
  echo 'Cannot parse BackgroundColor or SafariPinColor in favicon-src/palette.tex' >&2; exit 1;
}
BG="#$BGHEX"
PIN="#$PINHEX"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
compile() {
  local name="$1"
  (cd "$SRCDIR" && pdflatex -interaction=nonstopmode -halt-on-error \
    -output-directory "$TEMP" "$name.tex" > "$TEMP/$name.build-log") || {
      cat "$TEMP/$name.build-log" >&2
      exit 1
    }
}
compile compton-full
compile compton-small
compile compton-safari-mask

# Modern scalable favicon uses the small optical-size drawing, not tiny letters.
pdftocairo -svg "$TEMP/compton-small.pdf" "$IMG/favicon.svg"
# Full detail retained as an independently scalable reference asset.
pdftocairo -svg "$TEMP/compton-full.pdf" "$IMG/compton-diagram-labeled.svg"

# Cairo's exported SVG canvas can extend slightly past the TikZ background.
# Draw a full-canvas SVG rectangle UNDER the existing vectors, eliminating
# hairlines along the right and bottom edges. The mask SVG is intentionally
# excluded because Safari requires transparency around its artwork.
python3 - "$IMG/favicon.svg" "$IMG/compton-diagram-labeled.svg" "$BG" <<'PY_SVG'
import pathlib
import re
import sys
from html import escape

for filename in sys.argv[1:3]:
    path = pathlib.Path(filename)
    svg = path.read_text(encoding="utf-8")
    opening = re.search(r"<svg\b[^>]*>", svg, flags=re.DOTALL)
    if opening is None:
        raise SystemExit(f"Expected an <svg> root element in {filename}")
    # Insert before <defs> / all artwork, not over the Feynman diagram.
    rect = (f'\n<rect x="0" y="0" width="100%" height="100%" '
            f'fill="{escape(sys.argv[3], quote=True)}"/>\n')
    svg = svg[:opening.end()] + rect + svg[opening.end():]
    path.write_text(svg, encoding="utf-8")
PY_SVG

# Transparent monochrome mask for historical Safari macOS pinned tabs.
pdftocairo -svg "$TEMP/compton-safari-mask.pdf" "$TEMP/mask-raw.svg"
python3 "$ROOT/scripts/normalize-safari-svg.py" \
  "$TEMP/mask-raw.svg" "$IMG/safari-pinned-tab.svg"

# High resolution masters; downsample to each optical-size target.
pdftocairo -png -singlefile -r 950 "$TEMP/compton-small.pdf" "$TEMP/small"
pdftocairo -png -singlefile -r 950 "$TEMP/compton-full.pdf" "$TEMP/full"
for size in 16 32 48 64; do
  "${IM[@]}" "$TEMP/small.png" -filter Lanczos -resize "${size}x${size}!" \
    "$IMG/favicon-${size}x${size}.png"
done
for size in 120 152 167 180; do
  "${IM[@]}" "$TEMP/full.png" -filter Lanczos -resize "${size}x${size}!" \
    "$IMG/apple-touch-icon-${size}x${size}.png"
done
cp "$IMG/apple-touch-icon-180x180.png" "$IMG/apple-touch-icon.png"
cp "$IMG/apple-touch-icon.png" "$ROOT/apple-touch-icon.png"
# Historical precomposed Apple filename, only for older fallback probes.
cp "$IMG/apple-touch-icon.png" "$ROOT/apple-touch-icon-precomposed.png"

for size in 192 512; do
  "${IM[@]}" "$TEMP/full.png" -filter Lanczos -resize "${size}x${size}!" \
    "$IMG/android-chrome-${size}x${size}.png"
done
"${IM[@]}" "$TEMP/full.png" -filter Lanczos -resize 144x144! \
  "$IMG/mstile-144x144.png"
for size in 70 150 310; do
  "${IM[@]}" "$TEMP/full.png" -filter Lanczos -resize "${size}x${size}!" \
    "$IMG/mstile-${size}x${size}.png"
done

# Adaptive Android icon: illustration fits completely inside mask safe circle.
# Important: the small PDF-to-PNG source can contain a 1-2 pixel antialias
# halo on its own right/bottom boundary. If we center it on a 512px canvas,
# that halo becomes an INTERNAL square border, which outer-edge cleanup misses.
# Erase a five-pixel perimeter on the 280x280 illustration BEFORE padding.
# The actual diagram is far from the perimeter, so no artwork is lost.
"${IM[@]}" "$TEMP/small.png" -filter Lanczos -resize 280x280! \
  -alpha off -fill "$BG" -stroke none \
  -draw 'rectangle 0,0 279,4' \
  -draw 'rectangle 0,275 279,279' \
  -draw 'rectangle 0,0 4,279' \
  -draw 'rectangle 275,0 279,279' \
  -background "$BG" -gravity center -extent 512x512 \
  -type TrueColor -depth 8 \
  "PNG24:$IMG/maskable-icon-512x512.png"

# PDF/Cairo rasterization and Lanczos resampling can create a one-pixel
# antialiasing halo on the canvas edges (often visible on the right/bottom).
# All the listed output icons are SOLID-BACKGROUND designs and their artwork
# is inside the canvas, so paint exactly their outermost pixel rows/columns
# using the requested palette color. This preserves every internal pixel.
# Do NOT use this correction for the transparent Safari mask SVG.
fix_raster_edges() {
  local file="$1" dims w h tmp
  dims="$("${IM[@]}" "$file" -format '%w %h' info:)"
  read -r w h <<< "$dims"
  [[ "$w" =~ ^[0-9]+$ && "$h" =~ ^[0-9]+$ && "$w" -ge 2 && "$h" -ge 2 ]] || {
    echo "Unexpected image dimensions for $file: $dims" >&2
    exit 1
  }
  tmp="${file%.png}.edgetmp.png"
  "${IM[@]}" "$file" -alpha off -fill "$BG" -stroke none \
    -draw "rectangle 0,-1 $w,0" \
    -draw "rectangle 0,$((h-1)) $w,$h" \
    -draw "rectangle -1,0 0,$h" \
    -draw "rectangle $((w-1)),0 $w,$h" \
    "$tmp"
  mv "$tmp" "$file"
}
for file in \
  "$IMG"/favicon-{16,32,48,64}x{16,32,48,64}.png \
  "$IMG"/android-chrome-{192,512}x{192,512}.png \
  "$IMG"/apple-touch-icon-{120,152,167,180}x{120,152,167,180}.png \
  "$IMG"/apple-touch-icon.png \
  "$IMG"/mstile-{70,144,150,310}x{70,144,150,310}.png \
  "$IMG"/maskable-icon-512x512.png; do
  [[ -f "$file" ]] || continue
  fix_raster_edges "$file"
done
# Refresh legacy copies from corrected pixels.
cp "$IMG/apple-touch-icon.png" "$ROOT/apple-touch-icon.png"
cp "$IMG/apple-touch-icon.png" "$ROOT/apple-touch-icon-precomposed.png"

# True ICO containing 4 separate bitmap dimensions.
"${IM[@]}" \
  "$IMG/favicon-16x16.png" "$IMG/favicon-32x32.png" \
  "$IMG/favicon-48x48.png" "$IMG/favicon-64x64.png" \
  "$IMG/favicon.ico"
cp "$IMG/favicon.ico" "$ROOT/favicon.ico"

# Wide social sharing thumbnail (1200x630).
"${IM[@]}" -size 1200x630 "xc:$BG" \
  \( "$IMG/android-chrome-512x512.png" -resize 500x500 \) \
  -gravity center -composite -type TrueColor -depth 8 \
  "PNG24:$IMG/og-image.png"

cat > "$ROOT/manifest.webmanifest" <<MANIFEST
{
  "name": "Kishan Yerubandi",
  "short_name": "Kishan Yerubandi",
  "start_url": "/",
  "scope": "/",
  "display": "browser",
  "background_color": "$BG",
  "theme_color": "$BG",
  "icons": [
    {"src":"/assets/img/favicon.svg", "sizes":"any", "type":"image/svg+xml", "purpose":"any"},
    {"src":"/assets/img/android-chrome-192x192.png", "sizes":"192x192", "type":"image/png", "purpose":"any"},
    {"src":"/assets/img/android-chrome-512x512.png", "sizes":"512x512", "type":"image/png", "purpose":"any"},
    {"src":"/assets/img/maskable-icon-512x512.png", "sizes":"512x512", "type":"image/png", "purpose":"maskable"}
  ]
}
MANIFEST

# Legacy Internet Explorer / Windows pinned site tile configuration.
cat > "$ROOT/browserconfig.xml" <<BROWSERCONFIG
<?xml version="1.0" encoding="utf-8"?>
<browserconfig>
  <msapplication>
    <tile>
      <square70x70logo src="/assets/img/mstile-70x70.png"/>
      <square150x150logo src="/assets/img/mstile-150x150.png"/>
      <square310x310logo src="/assets/img/mstile-310x310.png"/>
      <TileColor>$BG</TileColor>
    </tile>
  </msapplication>
</browserconfig>
BROWSERCONFIG

cat > "$ROOT/scripts/head-favicon-snippet.liquid" <<HEAD
<!-- BEGIN COMPTON FAVICON SET -->
<link rel="icon" href="{{ '/favicon.ico' | relative_url }}" type="image/x-icon">
<link rel="icon" href="{{ '/assets/img/favicon-16x16.png' | relative_url }}" type="image/png" sizes="16x16">
<link rel="icon" href="{{ '/assets/img/favicon-32x32.png' | relative_url }}" type="image/png" sizes="32x32">
<link rel="icon" href="{{ '/assets/img/favicon-48x48.png' | relative_url }}" type="image/png" sizes="48x48">
<!-- Modern browsers use the simplified optical-size SVG. -->
<link rel="icon" href="{{ '/assets/img/favicon.svg' | relative_url }}" type="image/svg+xml" sizes="any">
<!-- Touch icons for historic and contemporary iOS/iPadOS clients. -->
<link rel="apple-touch-icon" href="{{ '/assets/img/apple-touch-icon-120x120.png' | relative_url }}" sizes="120x120">
<link rel="apple-touch-icon" href="{{ '/assets/img/apple-touch-icon-152x152.png' | relative_url }}" sizes="152x152">
<link rel="apple-touch-icon" href="{{ '/assets/img/apple-touch-icon-167x167.png' | relative_url }}" sizes="167x167">
<link rel="apple-touch-icon" href="{{ '/assets/img/apple-touch-icon.png' | relative_url }}" sizes="180x180">
<!-- Safari macOS pinned tabs: monochrome SVG, color is specified here. -->
<link rel="mask-icon" href="{{ '/assets/img/safari-pinned-tab.svg' | relative_url }}" color="$PIN">
<link rel="manifest" href="{{ '/manifest.webmanifest' | relative_url }}">
<meta name="msapplication-config" content="{{ '/browserconfig.xml' | relative_url }}">
<meta name="msapplication-TileColor" content="$BG">
<meta name="msapplication-TileImage" content="{{ '/assets/img/mstile-144x144.png' | relative_url }}">
<!-- END COMPTON FAVICON SET -->
HEAD

echo "Built: $IMG, root favicon.ico, Apple fallback, manifest, browserconfig.xml"
echo "Safari tint: $PIN; background: $BG"

# On subsequent builds, refresh installed HTML snippets if the site
# has already been configured. This keeps Safari tint synchronized.
if [[ -f "$ROOT/_includes/head.liquid" ]] && \
   grep -q 'BEGIN COMPTON FAVICON SET' "$ROOT/_includes/head.liquid"; then
  python3 "$ROOT/scripts/apply-site-changes.py"
fi
