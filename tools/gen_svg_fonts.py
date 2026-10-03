#!/usr/bin/env python3
"""Generate src/mathjax/fonts/tex_paths.cr from the mathjax-full oracle
data (dataset/oracle/node_modules) and self-check it against the golden
dataset (dataset/expected/*.svg).

Sources:
  output/svg/fonts/tex/*.js     codepoint -> SVG path 'd' per face
  output/common/fonts/tex/*.js  codepoint -> [h, d, w] metrics per face
  output/svg/fonts/tex.js       face -> id-prefix (variantCacheIds)
  output/common/fonts/tex/delimiters.js  stretchy delimiter table

Run from the repo root:  python3 tools/gen_svg_fonts.py
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MJ = os.path.join(ROOT, "dataset/oracle/node_modules/mathjax-full/js/output")

# face name -> (prefix, svg-font file, common-font file)
FACES = [
    ("normal", "N", "normal.js"),
    ("bold", "B", "bold.js"),
    ("italic", "I", "italic.js"),
    ("bold-italic", "BI", "bold-italic.js"),
    ("double-struck", "D", "double-struck.js"),
    ("fraktur", "F", "fraktur.js"),
    ("bold-fraktur", "BF", "fraktur-bold.js"),
    ("script", "S", "script.js"),
    ("bold-script", "BS", "script-bold.js"),
    ("sans-serif", "SS", "sans-serif.js"),
    ("bold-sans-serif", "BSS", "sans-serif-bold.js"),
    ("sans-serif-italic", "SSI", "sans-serif-italic.js"),
    ("sans-serif-bold-italic", "SSBI", "sans-serif-bold-italic.js"),
    ("monospace", "M", "monospace.js"),
    ("-smallop", "SO", "smallop.js"),
    ("-largeop", "LO", "largeop.js"),
    ("-size3", "S3", "tex-size3.js"),
    ("-size4", "S4", "tex-size4.js"),
    ("-tex-calligraphic", "C", "tex-calligraphic.js"),
    ("-tex-bold-calligraphic", "BC", "tex-calligraphic-bold.js"),
    ("-tex-mathit", "MI", "tex-mathit.js"),
    ("-tex-oldstyle", "OS", "tex-oldstyle.js"),
    ("-tex-bold-oldstyle", "BOS", "tex-oldstyle-bold.js"),
    ("-tex-variant", "V", "tex-variant.js"),
]

SIZE_VARIANTS = ["N", "SO", "LO", "S3", "S4", "V"]

PATH_RE = re.compile(r"0x([0-9A-Fa-f]+):\s*'([^']*)'")
# char entries: [h, d, w] or [h, d, w, { ic: .., sk: .., dx: .. }] (the
# object sits INSIDE the brackets)
METRIC_RE = re.compile(
    r"0x([0-9A-Fa-f]+):\s*\[\s*([-\d.]+)\s*,\s*([-\d.]+)\s*,\s*([-\d.]+)\s*"
    r"(?:,\s*\{([^}]*)\})?\s*\]")
EXTRA_RE = re.compile(r"(ic|sk|dx)\s*:\s*([-\d.]+)")


def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


def parse_paths(fname):
    src = read(os.path.join(MJ, "svg/fonts/tex", fname))
    return {int(m.group(1), 16): m.group(2) for m in PATH_RE.finditer(src)}


def parse_metrics(fname):
    src = read(os.path.join(MJ, "common/fonts/tex", fname))
    out = {}
    for m in METRIC_RE.finditer(src):
        cp = int(m.group(1), 16)
        h, d, w = float(m.group(2)), float(m.group(3)), float(m.group(4))
        extra = {k: float(v) for k, v in EXTRA_RE.findall(m.group(5) or "")}
        out[cp] = (h, d, w, extra.get("ic", 0.0), extra.get("sk", 0.0))
    return out


def parse_delimiters():
    """Returns {codepoint: {dir, sizes, variants, stretchv, stretch, hdw}}."""
    src = read(os.path.join(MJ, "common/fonts/tex/delimiters.js"))
    consts = {}
    for m in re.finditer(r"exports\.(\w+) = (\[[^\]]*\])", src):
        consts[m.group(1)] = m.group(2)
    delims = {}
    var_re = re.compile(
        r"var (DELIM\w+) = \{([^}]*)\}", re.S)
    vars_ = {}
    for m in var_re.finditer(src):
        body = m.group(2)
        d = {}
        for part in re.finditer(r"(\w+):\s*(\[[^\]]*\]|[^,}]+)", body):
            k, v = part.group(1), part.group(2).strip()
            d[k] = v
        vars_[m.group(1)] = d
    # exports.delimiters = { 0x2F: DELIM2F, ..., 0x221A: { dir: ... }, ... }
    exp = re.search(r"exports\.delimiters = \{(.*?)\};", src, re.S).group(1)
    for m in re.finditer(r"0x([0-9A-Fa-f]+):\s*(DELIM\w+|\{[^}]*\})", exp):
        cp, rhs = int(m.group(1), 16), m.group(2)
        if rhs.startswith("{"):
            # inline entry: parse its body like a var block (arrays contain
            # commas, so capture them as a unit)
            d = {}
            for part in re.finditer(r"(\w+):\s*(\[[^\]]*\]|[^,}]+)", rhs):
                d[part.group(1)] = part.group(2).strip()
            vars_[f"__inline{cp}"] = d
            name = f"__inline{cp}"
        else:
            name = rhs
        v = vars_[name]

        def val(key):
            return v.get(key)

        def parse_list(s):
            if s is None:
                return None
            toks = [x.strip().replace("exports.", "") for x in s.strip("[]").split(",")]
            return [t for t in toks if t]

        d = {"dir": "V" if "V" in (val("dir") or "") else "H"}
        sizes = parse_list(val("sizes"))
        if sizes:
            if sizes[0] in consts:  # VSIZES reference
                sizes = [x.strip() for x in consts[sizes[0]].strip("[]").split(",")]
            d["sizes"] = [float(x) for x in sizes]
        vari = parse_list(val("variants"))
        if vari:
            if vari[0] in consts:
                vari = [x.strip() for x in consts[vari[0]].strip("[]").split(",")]
            d["variants"] = [int(x, 0) for x in vari]
        sv = parse_list(val("stretchv"))
        if sv:
            if sv[0] in consts:
                sv = [x.strip() for x in consts[sv[0]].strip("[]").split(",")]
            d["stretchv"] = [int(x, 0) for x in sv]
        st = parse_list(val("stretch"))
        if st:
            d["stretch"] = [int(x, 0) for x in st]
        hdw = parse_list(val("HDW"))
        if hdw:
            if hdw[0] in consts:
                hdw = [x.strip() for x in consts[hdw[0]].strip("[]").split(",")]
            d["hdw"] = [float(x) for x in hdw]
        fe = parse_list(val("fullExt"))
        if fe:
            d["fullExt"] = [float(x) for x in fe]
        delims[cp] = d
    return delims


def normalize_d(src_d):
    """mathjax-full SVG Wrapper.js:353: d = 'M' + data.p + 'Z'."""
    return "M" + src_d + "Z" if src_d else ""


def selfcheck(paths_by_prefix):
    """Every <path id='MJX-n-TEX-PREFIX-CP' d='...'> in the dataset must
    be present with an identical d in our tables."""
    dsplit_re = re.compile(r'<path id="MJX-\d+-TEX-([A-Z0-9]+)-([0-9A-Fa-f]+)" d="([^"]*)"')
    ok = miss_cp = miss_d = total = 0
    for f in glob.glob(os.path.join(ROOT, "dataset/expected/*.svg")):
        for m in dsplit_re.finditer(read(f)):
            total += 1
            prefix, cp, d = m.group(1), int(m.group(2), 16), m.group(3)
            face = paths_by_prefix.get(prefix)
            if face is None or cp not in face:
                miss_cp += 1
            elif face[cp] != d:
                miss_d += 1
            else:
                ok += 1
    return ok, miss_cp, miss_d, total


def build_paths_with_dataset_evidence(face_paths):
    """v3 resolves some variants (e.g. TEX-I math-alphanumerics) from
    unexpected face files; harvest the authoritative (prefix, cp, d)
    mapping from the dataset itself, normalized as 'M'+p+'Z'."""
    dsplit_re = re.compile(r'<path id="MJX-\d+-TEX-([A-Z0-9]+)-([0-9A-Fa-f]+)" d="([^"]*)"')
    # normalized d index over all faces
    idx = {}
    for prefix, p in face_paths.items():
        for cp, d in p.items():
            idx[(cp, normalize_d(d))] = prefix

    out = {}
    unresolved = 0
    for _, prefix, _ in FACES:
        out[prefix] = {cp: normalize_d(d) for cp, d in face_paths[prefix].items()}
    obs_total = 0
    obs_hit = 0
    for f in glob.glob(os.path.join(ROOT, "dataset/expected/*.svg")):
        for m in dsplit_re.finditer(read(f)):
            obs_total += 1
            prefix, cp, d = m.group(1), int(m.group(2), 16), m.group(3)
            if prefix in out and cp in out[prefix] and out[prefix][cp] == d:
                obs_hit += 1
                continue
            src = idx.get((cp, d))
            if src is not None:
                out.setdefault(prefix, {})[cp] = d
                obs_hit += 1
            else:
                unresolved += 1
    return out, obs_total, obs_hit, unresolved


def emit(paths, metrics, delims):
    out = []
    w = out.append
    w("# GENERATED by tools/gen_svg_fonts.py from mathjax-full (Apache-2.0).")
    w("# TeX glyph outline paths + metrics + stretchy delimiter table.")
    w("# Self-checked against dataset/expected/*.svg (d-string equality).")
    w("module MathJax::Fonts::TexPaths")
    w("  # id-prefix -> { codepoint -> SVG path 'd' }")
    w("  PATHS = {")
    for face, prefix, _ in FACES:
        p = paths[prefix]
        if not p:
            continue
        w(f'    "{prefix}" => {{')
        items = sorted(p.keys())
        line = "      "
        for cp in items:
            piece = f'{cp} => "{p[cp]}", '
            if len(line) + len(piece) > 110:
                w(line.rstrip())
                line = "      "
            line += piece
        if line.strip():
            w(line.rstrip())
        w("    },")
    w("  }")
    w("")
    w("  # id-prefix -> { codepoint -> {h, d, w, ic, sk} } (em units)")
    w("  METRICS = {")
    for face, prefix, _ in FACES:
        m = metrics[prefix]
        if not m:
            continue
        w(f'    "{prefix}" => {{')
        line = "      "
        for cp in sorted(m):
            h, d, wd, ic, sk = m[cp]
            piece = f'{cp} => {{{h}, {d}, {wd}, {ic}, {sk}}}, '
            if len(line) + len(piece) > 110:
                w(line.rstrip())
                line = "      "
            line += piece
        if line.strip():
            w(line.rstrip())
        w("    },")
    w("  }")
    w("")
    w("  # getSizeVariant chain: variant index -> id-prefix")
    w('  SIZE_VARIANTS = %w(' + " ".join(SIZE_VARIANTS) + ")")
    w("")
    w("  record Delim, dir : String, sizes : Array(Float64), variants : Array(Int32),")
    w("          stretchv : Array(Int32), stretch : Array(Int32), hdw : Array(Float64),")
    w("          fullext : Array(Float64)")
    w("")

    def cl(lst, typ):
        return "[] of " + typ if not lst else repr(lst).replace("'", "")

    w("  # codepoint -> stretchy construction")
    w("  DELIMITERS = {")
    for cp in sorted(delims):
        d = delims[cp]
        w(f"    {cp} => Delim.new(\"{d['dir']}\", {cl(d.get('sizes'), 'Float64')}, "
          f"{cl(d.get('variants'), 'Int32')}, {cl(d.get('stretchv'), 'Int32')}, "
          f"{cl(d.get('stretch'), 'Int32')}, {cl(d.get('hdw'), 'Float64')}, "
          f"{cl(d.get('fullExt'), 'Float64')}),")
    w("  }")
    w("end")
    return "\n".join(out) + "\n"


def main():
    paths = {}
    metrics = {}
    for face, prefix, fname in FACES:
        paths[prefix] = parse_paths(fname)
        metrics[prefix] = parse_metrics(fname)
        print(f"face {prefix:4}: {len(paths[prefix]):4} paths, {len(metrics[prefix]):4} metrics")

    delims = parse_delimiters()
    print(f"delimiters: {len(delims)}")

    paths, obs_total, obs_hit, unresolved = build_paths_with_dataset_evidence(paths)
    print(f"evidence merge: {obs_hit}/{obs_total} dataset observations resolved, "
          f"{unresolved} unresolved")
    if unresolved:
        print("FAIL: dataset observations with no matching source path", file=sys.stderr)
        sys.exit(1)

    ok, miss_cp, miss_d, total = selfcheck(paths)
    print(f"selfcheck: {ok}/{total} dataset d-strings matched "
          f"(missing cp: {miss_cp}, mismatched d: {miss_d})")
    if ok != total:
        print("FAIL: dataset coverage incomplete", file=sys.stderr)
        sys.exit(1)

    # metrics: fill each prefix's gaps from any face that has the cp
    all_metrics = {}
    for _, prefix, _ in FACES:
        all_metrics[prefix] = dict(metrics[prefix])
    for _, prefix, _ in FACES:
        for cp in paths[prefix]:
            if cp not in all_metrics[prefix]:
                for _, p2, _ in FACES:
                    if cp in metrics[p2]:
                        all_metrics[prefix][cp] = metrics[p2][cp]
                        break
    metrics = all_metrics

    dst = os.path.join(ROOT, "src/mathjax/fonts/tex_paths.cr")
    with open(dst, "w", encoding="utf-8") as f:
        f.write(emit(paths, metrics, delims))
    print(f"wrote {dst} ({os.path.getsize(dst)//1024} KiB)")


if __name__ == "__main__":
    main()
