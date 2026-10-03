#!/usr/bin/env python3
"""Dump g/use structure of an SVG (kind, transform, data-c)."""
import re, sys
s = open(sys.argv[1]).read()
for m in re.finditer(r'<(g|use) ([^>]*)>', s):
    tag, attrs = m.group(1), m.group(2)
    if tag == 'g':
        kind = re.search(r'data-mml-node="(\w+)"', attrs)
        tr = re.search(r'transform="([^"]*)"', attrs)
        if kind or tr:
            print('g', kind.group(1) if kind else '?', tr.group(1) if tr else '')
    else:
        c = re.search(r'data-c="([0-9A-Fa-f]+)"', attrs)
        if c:
            print('   use', c.group(1))
