#!/usr/bin/env python3
"""Safely install/refresh Compton favicon HTML and OG metadata in this Jekyll repo.

First run: replaces the exact existing al-folio favicon conditional.
Later runs: refreshes only the marked favicon section (including Safari tint).
Makes backups in favicon-src/backups/ (ignored by Git).
"""
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HEAD = ROOT / '_includes/head.liquid'
META = ROOT / '_includes/metadata.liquid'
CONF = ROOT / '_config.yml'
SNIPPET = ROOT / 'scripts/head-favicon-snippet.liquid'
BACKUPS = ROOT / 'favicon-src/backups'
old_re = re.compile(r'(?s)\{%\s*if site\.icon\.size <= 4\s*%\}.*?\{%\s*endif\s*%\}')
installed_re = re.compile(r'(?s)<!-- BEGIN COMPTON FAVICON SET -->.*?<!-- END COMPTON FAVICON SET -->')

def replace_unique(src, pattern, repl, label):
    out, count = re.subn(pattern, lambda m: repl, src, count=1, flags=re.M)
    if count != 1:
        raise RuntimeError(f'Cannot locate expected {label}; edit manually rather than risk unrelated code')
    return out

def main():
    for p in [HEAD, META, CONF, SNIPPET]:
        if not p.is_file():
            raise RuntimeError(f'Missing {p}. Run this from a complete Jekyll repo after generating the icons.')
    files = {p: p.read_text(encoding='utf-8') for p in [HEAD, META, CONF]}
    snippet = SNIPPET.read_text(encoding='utf-8').strip()
    h = files[HEAD]
    if installed_re.search(h):
        h = installed_re.sub(lambda m: snippet, h, count=1)
    else:
        match = old_re.search(h)
        if not match:
            raise RuntimeError('Old favicon conditional not found. If you customized head.liquid, insert scripts/head-favicon-snippet.liquid manually.')
        h = h[:match.start()] + snippet + h[match.end():]
    files[HEAD] = h

    c = files[CONF]
    c = replace_unique(c, r'^serve_og_meta:.*$',
                       'serve_og_meta: true # Enable link-preview metadata', 'serve_og_meta')
    c = replace_unique(c, r'^og_image:.*$',
                       'og_image: https://kishanyerubandi.github.io/assets/img/og-image.png', 'og_image')
    # Exclude the editable masters and generator scripts from the published site.
    for path in ['favicon-src/', 'scripts/']:
        if not re.search(r'^  - ' + re.escape(path) + r'\s*$', c, flags=re.M):
            c = replace_unique(c, r'^exclude:\s*$', 'exclude:\n  - ' + path, 'exclude list')
    files[CONF] = c

    m = files[META]
    if 'property="og:image:width"' not in m:
        extra = ('\n    <meta property="og:image:type" content="image/png">'
                 '\n    <meta property="og:image:width" content="1200">'
                 '\n    <meta property="og:image:height" content="630">'
                 '\n    <meta property="og:image:alt" content="Compton-scattering Feynman diagram">')
        match = re.search(r'(?m)^(\s*<meta property="og:image" content="[^\n]+">)', m)
        if not match:
            raise RuntimeError('Could not locate existing og:image metadata in metadata.liquid')
        m = m[:match.end(1)] + extra + m[match.end(1):]
    files[META] = m

    # No changes are written until the preflight validation above succeeds.
    BACKUPS.mkdir(parents=True, exist_ok=True)
    for p, updated in files.items():
        if updated != p.read_text(encoding='utf-8'):
            backup = BACKUPS / (p.parent.name.strip('_') + '-' + p.name)
            if not backup.exists():
                shutil.copyfile(p, backup)
            p.write_text(updated, encoding='utf-8')
            print('Updated', p.relative_to(ROOT))
    print('Favicon HTML and Open Graph settings are configured.')

if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        raise SystemExit('ERROR: ' + str(e))
