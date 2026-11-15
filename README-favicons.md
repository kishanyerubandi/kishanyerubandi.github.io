# Kishan Yerubandi: Compton-scattering favicon workflow (v2)

This package is designed to be **extracted into the root** of the existing
`kishanyerubandi.github.io` repository. It does NOT publish or commit anything.
It preserves the labeled Compton diagram for large graphics, adds an optical-
size version without labels for 16–64 px icons, and creates a monochrome,
transparent pinned-tab SVG for historical macOS Safari.

## 1. Requirements (Ubuntu)

```bash
sudo apt update
sudo apt install texlive-latex-extra texlive-pictures poppler-utils imagemagick python3
```

The script uses `pdflatex`, `pdftocairo`, `magick` (or `convert`), and Python 3.
No Python packages or third-party web services are required.

## 2. Place files in the existing repo

From the root of your cloned repository:

```bash
unzip /path/to/compton-favicon-workflow-v2.zip -d .
```

The directory layout will include:

```
favicon-src/
    palette.tex                 <-- edit ALL colors here
    compton-full.tex           <-- full labeled drawing
    compton-small.tex          <-- 16-64px drawing wrapper
    compton-safari-mask.tex    <-- pinned-tab wrapper (transparent)
    compton-small-art.tex      <-- shared shape of small + Safari icons
scripts/
    build-favicons.sh
    apply-site-changes.py
    normalize-safari-svg.py
    head-favicon-snippet.liquid
assets/img/
    favicon.svg
    safari-pinned-tab.svg
    favicon-16x16.png
    favicon-32x32.png
    ... and other generated image files
favicon.ico
manifest.webmanifest
browserconfig.xml
apple-touch-icon.png
apple-touch-icon-precomposed.png
```

## 3. Generate all images

```bash
bash scripts/build-favicons.sh
```

This runs 3 short LaTeX compilations, generates the SVGs, PNGs, multi-size
`favicon.ico`, Android maskable icon, legacy Windows tile art, and Open Graph
preview. The Safari mask has transparent background, black paths, and an
exact `viewBox="0 0 16 16"`.

**Changing colors:** edit the eight `\definecolor` lines in
`favicon-src/palette.tex`, then rerun the same build command. All three TeX
entry points read the same palette. The Safari pin art stays black/transparent;
its rendered **tint** comes from `SafariPinColor` in `palette.tex` and is written
into the HTML link automatically. The script does not overwrite your source.

**Changing geometry:** edit `favicon-src/compton-full.tex` for labels and larger
renderings. Edit `favicon-src/compton-small-art.tex` for both the 16–64px favicon
and Safari mask. The masks and simplified favicon use the same TikZ drawing.

## 4. Configure this specific Jekyll/al-folio site

With your repository files `_includes/head.liquid`, `_includes/metadata.liquid`
and `_config.yml` present, run **once**:

```bash
python3 scripts/apply-site-changes.py
```

This script:

* Replaces only the existing `{% if site.icon.size <= 4 %} ... {% endif %}`
  favicon block in `_includes/head.liquid`, using
  `scripts/head-favicon-snippet.liquid`.
* Adds Safari `<link rel="mask-icon" ...>` with the generated tint.
* Advertises browser-tab SVG/PNG/ICO, iOS Apple touch icons,
  the Android manifest, and legacy Windows tile configuration.
* Enables Open Graph metadata (`serve_og_meta: true`) and sets `og_image` to
  `https://kishanyerubandi.github.io/assets/img/og-image.png`.
* Adds `og:image` dimensions and alt text to the existing metadata template.
* Excludes `scripts/` and `favicon-src/` from the Jekyll-published site.
* Creates backups of edited files in `favicon-src/backups/` (ignored by Git).

The installer is idempotent: subsequent runs refresh its own marked block
instead of inserting duplicate tags. If your HTML differs significantly from
the inspected upstream file, the installer stops with an error rather than
overwrite unknown customizations; insert the generated snippet manually.

After this one-time install, simply running `bash scripts/build-favicons.sh`
will ALSO refresh the already-installed block if you have changed the Safari
tint color. You may optionally rerun `python3 scripts/apply-site-changes.py`.

The original `icon: "favicon-32x32.png"` key in `_config.yml` is harmless but
is no longer consulted by the new favicon block.

## 5. Inspect, commit, and publish

Before committing, examine `assets/img/favicon-16x16.png` at **actual size**;
inspect the large Apple icon and confirm its labels are legible.

```bash
git status --short
git diff -- _includes/head.liquid _includes/metadata.liquid _config.yml
git add assets/img favicon-src scripts favicon.ico apple-touch-icon.png \
  apple-touch-icon-precomposed.png manifest.webmanifest browserconfig.xml
# Add the changed Jekyll files, too:
git add _includes/head.liquid _includes/metadata.liquid _config.yml
git commit -m "Add accessible-size Compton favicons and legacy browser icons"
git push
```

If any file had already been customized, review the diff before committing.
Do not add `favicon-src/backups/`, which is intentionally ignored.

After GitHub Pages deploys, check these URLs:

- https://kishanyerubandi.github.io/favicon.ico
- https://kishanyerubandi.github.io/assets/img/favicon.svg
- https://kishanyerubandi.github.io/assets/img/safari-pinned-tab.svg
- https://kishanyerubandi.github.io/assets/img/favicon-16x16.png
- https://kishanyerubandi.github.io/apple-touch-icon.png
- https://kishanyerubandi.github.io/manifest.webmanifest
- https://kishanyerubandi.github.io/browserconfig.xml
- https://kishanyerubandi.github.io/assets/img/og-image.png

View Page Source and verify there is only one marked favicon block and a single
Open Graph `og:image` meta entry. Browser favicons and social previews may stay
cached after deployment.

## What the browser-specific extras do

* Small PNG and SVG: crisp rendering at 16, 32, 48 and 64 px.
* Multi-size ICO at the site root: older tab/bookmark clients and automatic
  `/favicon.ico` requests.
* Safari pinned-tab mask: an entirely transparent SVG outside black lines.
  Safari uses the `color` attribute to tint it.
* Apple touch icons: 120, 152, 167, 180 px plus root-level fallback filenames.
* Android: 192/512 px ordinary icons, plus a specially padded 512 px maskable
  icon that stays within the central 40%-radius circle safe zone.
* Windows: `browserconfig.xml`, tile icons (70, 144, 150, 310 px), and legacy
  tile meta tags.
* Link previews: `og-image.png` (1200 × 630) and Jekyll Open Graph metadata.

These assets maximize practical compatibility; not every old browser honors
all hints, and a static Jekyll site does not become an offline-capable PWA
merely by including a manifest.

The old `feynman-diag-compton-scattering-03.png` need not be deleted; it is a
useful historical reference and does not conflict with this workflow.
