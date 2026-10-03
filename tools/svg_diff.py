#!/usr/bin/env python3
"""Position/structure diff: our v3-structure SVG vs the MathJax v3
reference (dataset/expected).

For each formula:
  - glyph multiset comparison (face-prefix + codepoint),
  - absolute use positions, y-up user units, after aligning by the
    matched glyphs' centroid (translations/padding differ by design).

Usage: python3 tools/svg_diff.py [ours-dir] [expected-dir]
"""
import glob
import os
import re
import sys
import xml.etree.ElementTree as ET

import numpy as np

SVG_NS = "{http://www.w3.org/2000/svg}"
XLINK_HREF = "{http://www.w3.org/1999/xlink}href"

USE_RE = re.compile(
    r'<use[^>]*xlink:href="#MJX-\d+-TEX-([A-Z0-9]+)-([0-9A-Fa-f]+)"'
    r'[^>]*transform="([^"]*)"')


def parse_transform(s):
    m = np.array([1.0, 0.0, 0.0, 1.0, 0.0, 0.0])
    for name, args in re.findall(r"(\w+)\s*\(([^)]*)\)", s or ""):
        v = [float(x) for x in re.split(r"[\s,]+", args.strip()) if x]
        t = np.array(m)
        if name == "translate":
            t = np.array([1, 0, 0, 1, v[0], v[1] if len(v) > 1 else 0.0])
        elif name == "scale":
            t = np.array([v[0], 0, 0, v[1] if len(v) > 1 else v[0], 0, 0])
        elif name == "matrix":
            t = np.array(v[:6])
        m = matmul(m, t)
    return m


def matmul(a, b):
    """a after b: point -> b -> a (x' = a0*x + a2*y + a4)."""
    return np.array([
        a[0]*b[0] + a[2]*b[1], a[1]*b[0] + a[3]*b[1],
        a[0]*b[2] + a[2]*b[3], a[1]*b[2] + a[3]*b[3],
        a[0]*b[4] + a[2]*b[5] + a[4], a[1]*b[4] + a[3]*b[5] + a[5],
    ])


def ours_glyphs(src):
    """Our flat emission: <use transform="translate(...) scale(...)"> plus
    nested stretch <svg x y w h viewBox><use transform="scale(...)">."""
    root = ET.fromstring(src)
    out = []

    def walk(el, m, is_root=False):
        own = parse_transform(el.get("transform", ""))
        if el.tag == f"{SVG_NS}use":
            href = el.get("href") or el.get(XLINK_HREF) or ""
            mm = re.match(r"#MJX-\d+-TEX-([A-Z0-9]+)-([0-9A-Fa-f]+)", href)
            if mm:
                t = matmul(m, own)
                out.append((mm.group(1), int(mm.group(2), 16), t[4], -t[5], t[0]))
            return
        m = matmul(m, own)
        if el.tag == f"{SVG_NS}svg" and el.get("viewBox") is not None and not is_root:
            vb = [float(x) for x in el.get("viewBox").replace(",", " ").split()]
            w = float(re.sub(r"[^\d.\-]", "", el.get("width", "1")) or 1)
            h = float(re.sub(r"[^\d.\-]", "", el.get("height", "1")) or 1)
            x = float(re.sub(r"[^\d.\-]", "", el.get("x", "0")) or 0)
            y = float(re.sub(r"[^\d.\-]", "", el.get("y", "0")) or 0)
            sx = w / vb[2] if vb[2] > 0 and w > 0 else 1.0
            sy = h / vb[3] if vb[3] > 0 and h > 0 else 1.0
            m = matmul(m, np.array([1, 0, 0, 1, -vb[0], -vb[1]]))
            m = matmul(m, np.array([sx, 0, 0, sy, 0, 0]))
            m = matmul(m, np.array([1, 0, 0, 1, x, y]))
        for c in el:
            walk(c, m)

    walk(root, np.array([1.0, 0.0, 0.0, 1.0, 0.0, 0.0]), is_root=True)
    return out


def expected_glyphs(path):
    root = ET.parse(path).getroot()
    out = []

    def walk(el, m, is_root=False):
        m = matmul(m, parse_transform(el.get("transform", "")))
        # the ROOT viewBox maps user units to the canvas (width in ex):
        # positions are compared in user units, so skip it; nested stretch
        # <svg> viewBox mappings ARE applied
        if el.tag == f"{SVG_NS}svg" and el.get("viewBox") is not None and not is_root:
            vb = [float(x) for x in el.get("viewBox").replace(",", " ").split()]
            w = float(re.sub(r"[^\d.\-]", "", el.get("width", "1")) or 1)
            h = float(re.sub(r"[^\d.\-]", "", el.get("height", "1")) or 1)
            x = float(re.sub(r"[^\d.\-]", "", el.get("x", "0")) or 0)
            y = float(re.sub(r"[^\d.\-]", "", el.get("y", "0")) or 0)
            sx = w / vb[2] if vb[2] > 0 and w > 0 else 1.0
            sy = h / vb[3] if vb[3] > 0 and h > 0 else 1.0
            m = matmul(m, np.array([1, 0, 0, 1, -vb[0], -vb[1]]))
            m = matmul(m, np.array([sx, 0, 0, sy, 0, 0]))
            m = matmul(m, np.array([1, 0, 0, 1, x, y]))
        if el.tag == f"{SVG_NS}use":
            href = el.get("href") or el.get(XLINK_HREF) or ""
            mm = re.match(r"#MJX-\d+-TEX-([A-Z0-9]+)-([0-9A-Fa-f]+)", href)
            if mm:
                t = matmul(m, parse_transform(
                    f'translate({el.get("x", "0")},{el.get("y", "0")})'))
                out.append((mm.group(1), int(mm.group(2), 16), t[4], -t[5], t[0]))
        for c in el:
            walk(c, m)

    walk(root, np.array([1.0, 0.0, 0.0, 1.0, 0.0, 0.0]), is_root=True)
    return out


def match(a, b):
    """Greedy nearest matching by (prefix, cp) then distance."""
    used = [False] * len(b)
    pairs = []
    for g in a:
        best, bd = None, 1e18
        for i, h in enumerate(b):
            if used[i] or h[0] != g[0] or h[1] != g[1]:
                continue
            d = (h[2] - g[2]) ** 2 + (h[3] - g[3]) ** 2
            if d < bd:
                bd, best = d, i
        if best is not None:
            used[best] = True
            pairs.append((g, b[best]))
    return pairs, sum(used)


def main(ours_dir, exp_dir):
    med_deltas, max_deltas, files_ok, files = [], [], 0, 0
    tot_ours = tot_exp = tot_matched = 0
    worst = []
    for f in sorted(glob.glob(os.path.join(ours_dir, "*.svg"))):
        name = os.path.basename(f)
        exp = os.path.join(exp_dir, name)
        if not os.path.exists(exp):
            continue
        files += 1
        a = ours_glyphs(open(f).read())
        b = expected_glyphs(exp)
        pairs, n = match(a, b)
        tot_ours += len(a)
        tot_exp += len(b)
        tot_matched += n
        if not pairs:
            worst.append((1e9, name, 0, len(a), len(b)))
            continue
        # align by centroid
        ca = np.mean([[g[2], g[3]] for g, _ in pairs], axis=0)
        cb = np.mean([[h[2], h[3]] for _, h in pairs], axis=0)
        d = [np.hypot(h[2] - g[2] - (cb[0] - ca[0]),
                      h[3] - g[3] - (cb[1] - ca[1])) for g, h in pairs]
        med, mx = float(np.median(d)), float(np.max(d))
        med_deltas.append(med)
        max_deltas.append(mx)
        if med < 100:  # < 0.1 em median residual
            files_ok += 1
        worst.append((med, name, len(pairs), len(a), len(b)))

    worst.sort(reverse=True)
    print(f"files compared: {files}, median<100 units: {files_ok}")
    print(f"glyphs: ours {tot_ours}, expected {tot_exp}, matched {tot_matched} "
          f"({100*tot_matched/max(1,tot_exp):.1f}% of expected)")
    if med_deltas:
        print(f"position residual (units, 1000 = 1em), after centroid align:")
        print(f"  median-of-medians {np.median(med_deltas):.1f}, "
              f"p95 {np.percentile(med_deltas, 95):.1f}, max {max(max_deltas):.1f}")
    print("worst files (median units, matched/ours/expected):")
    for med, name, np_, na, nb in worst[:8]:
        print(f"  {name}: {med:.0f}  {np_}/{na}/{nb}")


if __name__ == "__main__":
    ours = sys.argv[1] if len(sys.argv) > 1 else "/tmp/mj_v3/ours"
    exp = sys.argv[2] if len(sys.argv) > 2 else "dataset/expected"
    main(ours, exp)
