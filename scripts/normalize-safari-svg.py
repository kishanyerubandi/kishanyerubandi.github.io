#!/usr/bin/env python3
"""Normalize transparent, black vector artwork to Safari's 0..16 SVG mask.
The input is the vector PDF conversion from the dedicated TikZ mask master.
"""
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

if len(sys.argv) != 3:
    raise SystemExit('Usage: normalize-safari-svg.py raw.svg safari-pinned-tab.svg')
infile, outfile = map(Path, sys.argv[1:])
ET.register_namespace('', 'http://www.w3.org/2000/svg')
ET.register_namespace('xlink', 'http://www.w3.org/1999/xlink')
root = ET.parse(infile).getroot()
box = root.get('viewBox')
if not box:
    raise SystemExit('Input SVG has no viewBox')
x, y, width, height = list(map(float, box.strip().split()))
if abs(width - height) > 0.02:
    raise SystemExit('Safari mask geometry is not square')

# Reject any unexpected white or colored paint. The source must be black only.
s = ET.tostring(root, encoding='unicode').lower()
for color in ['rgb(100%, 100%, 100%)', '#ffffff', '#fff', 'white']:
    if color in s:
        raise SystemExit('Unexpected white paint in transparent mask: ' + color)

ns = '{http://www.w3.org/2000/svg}'
# Make root itself the exact Safari 16x16 viewport. Keep original vector paths
# and their defs, but put artwork under a single scaled layer.
root.set('viewBox', '0 0 16 16')
root.set('width', '16')
root.set('height', '16')
for key in list(root.attrib):
    if key not in ('viewBox', 'width', 'height'):
        del root.attrib[key]
layer = ET.Element(ns + 'g', {'transform': f'translate({-x*16/width:.8f} {-y*16/height:.8f}) scale({16/width:.9f})'})
for child in list(root):
    if child.tag != ns + 'defs':
        root.remove(child)
        layer.append(child)
root.append(layer)
ET.ElementTree(root).write(outfile, encoding='utf-8', xml_declaration=True)
