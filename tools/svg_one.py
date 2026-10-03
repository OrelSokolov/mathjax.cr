#!/usr/bin/env python3
"""Per-glyph positional dump for one file: ours vs expected.
Usage: python3 tools/svg_one.py <name.svg>
"""
import os
import sys
import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from svg_diff import ours_glyphs, expected_glyphs, match

name = sys.argv[1]
ours = ours_glyphs(open(f"/tmp/mj_v3/ours/{name}").read())
exp = expected_glyphs(f"dataset/expected/{name}")
pairs, n = match(ours, exp)
ca = np.mean([[g[2], g[3]] for g, _ in pairs], axis=0)
cb = np.mean([[h[2], h[3]] for _, h in pairs], axis=0)
off = cb - ca
print(f"{name}: ours={len(ours)} exp={len(exp)} matched={n} centroid-offset=({off[0]:.1f},{off[1]:.1f})")
rows = []
for g, h in pairs:
    dx = h[2] - g[2] - off[0]
    dy = h[3] - g[3] - off[1]
    rows.append((np.hypot(dx, dy), g[0], g[1], g[2], g[3], h[2], h[3], dx, dy))
rows.sort(reverse=True)
for r in rows[:25]:
    print(f"{r[1]}-{r[2]:04X} ours=({r[3]:8.1f},{r[4]:8.1f}) exp=({r[5]:8.1f},{r[6]:8.1f}) d=({r[7]:8.1f},{r[8]:8.1f}) |d|={r[0]:.1f}")
