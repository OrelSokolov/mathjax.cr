# mathjax.cr

[Русская версия](README.ru.md)

A Crystal port of the [MathJax](https://github.com/mathjax/MathJax) (v3) core:
**TeX / AsciiMath / MathML → internal MML tree → MathML / HTML / SVG**.

Ported after the `ts/` sources of
[mathjax-src](https://github.com/mathjax/mathjax-src) and the MathJax v2 font
data:

## Inputs

- **TeX parser** (`input/tex`): tokenizer, `{...}` groups, `^`/`_` scripts,
  primes, the `\frac` family, generalized fractions (`a \over b`, `\atop`,
  `\choose`, `\above`, `\genfrac`), `\sqrt`/`\root`, `\left...\right` with
  `\middle`, environments (`matrix/pmatrix/bmatrix/vmatrix/Vmatrix/cases/
  array/aligned/...`), fonts (`\mathrm`, `\mathbf`, `\mathbb`, ...), accents
  (`\vec`, `\hat`, `\overline`, `\overrightarrow`, ...), spacing, `\text`,
  `\stackrel`, `\overbrace`/`\underbrace`, `\phantom`, `\boxed`, big
  operators with limits (`munderover`, `\limits`/`\nolimits`), `\def`/
  `\newcommand` macros (with `#1..#9`).
- **Extensions**: `color` (`\color`, `\textcolor`, `\definecolor` with
  rgb/RGB/gray/HTML/cmyk models, `\colorbox`, `\fcolorbox`), `cancel`
  (`\cancel`, `\bcancel`, `\xcancel`, `\sout`), a `physics` subset
  (`\abs`, `\norm`, `\dv`, `\pdv`, `\dd`, `\bra`, `\ket`, `\braket`, `\mel`,
  `\comm`, ... — enabled via `physics: true` / `--physics`).
- **AsciiMath** (an `input/asciimath` subset): `a/b` fractions, `^`/`_`,
  greek names, `sum/prod/int` with limits, relations and arrows
  (`<= >= != -> => <=>`), `sqrt`, `hat/bar/vec/ul(...)`, `|x|`, `floor/ceil`,
  `[[a,b],[c,d]]` matrices, `"..."` text.
- **MathML input** (`input/mml`): XML → tree (round-trips with the
  serializer).

## Outputs

- **MathML** — tree serialization.
- **HTML** — a simplified CommonHTML analogue: spans + CSS (`MathJax.css`).
- **SVG** — two modes (`MathJax.to_svg(tex, paths: ...)`):
  - `paths: false` (default): metrics-based typesetting with `<text>` +
    system fonts;
  - `paths: true`: MathJax v3 structure — glyph outline `<path>`s in a
    single `<defs>` + `<use xlink:href>`, sized in `ex`, colored via
    `currentColor`. The layout engine is a port of the mathjax-full v3
    common wrappers (TeX spacing matrix, fraction/script/sqrt geometry,
    mtable layout, stretchy delimiter assembly, mo/accent remaps).
    Rasterizes by nanosvg.cr (egui-cr) with no fonts installed. Glyph
    outlines come from the TeX font data generated out of mathjax-full
    (`tools/gen_svg_fonts.py`, self-checked against the dataset:
    7920/7920 d-strings byte-equal). Positional verification over the
    1000-formula corpus: 96.6% of reference glyphs matched, median
    residual 13 units (1 em = 1000 units). See `SVG_V3_PLAN.md`.

## Not ported

a11y (SRE — a separate large system), CHTML (the SVG output has two
modes: `<text>` + system fonts, and the v3-structure path output —
see "Outputs"), the `action`, `autobold`,
`bbox`, `bussproofs`, `cancel` color options, `centernot`, `colortbl`,
`empheq`, `extpfeil`, `gensymb`, `html`, `mathtools`, `mhchem`,
`newcommand` conditionals, `noerrors` configurations, `upgreek`, `verb`
extensions and the full AMS table (~180 base commands covered).

## Installation

```yaml
dependencies:
  mathjax:
    git: https://github.com/OrelSokolov/mathjax.cr
```

## Usage

```crystal
require "mathjax"

MathJax.to_mathml("\\frac{1}{2}")                   # MathML
MathJax.to_mathml("x^2", display: true)
MathJax.to_html("\\sqrt{2}")                        # HTML + mjx-* classes
MathJax.to_svg("\\frac{a+b}{c}")                    # SVG with TeX metrics
MathJax.css                                         # CSS for the HTML output
MathJax.parse("\\sum_{i=1}^n i")                    # => MathJax::Mml::Node
MathJax.to_mathml("\\abs{x}", physics: true)        # physics extension
MathJax::Mml::Serializer.call(
  MathJax.parse_asciimath("sum_(i=1)^n i"))         # AsciiMath input
MathJax.from_mathml("<math>...</math>")             # MathML input
MathJax::Fonts.width('a', "math_italic")            # 0.529 (TeX metrics)
```

Parse errors: `MathJax::TeX::TexError`,
`MathJax::AsciiMath::AsciiMathError`, `MathJax::Mml::MathmlError`.

## CLI

```sh
crystal run src/cli.cr -- --html --display < formula.tex
crystal run src/cli.cr -- --svg < formula.tex
crystal run src/cli.cr -- --physics --mml <<< '\dv{f}{x}'
crystal run src/cli.cr -- --ascii --mml <<< 'sum_(i=1)^n i'
echo '\frac{-b\pm\sqrt{b^2-4ac}}{2a}' | crystal run src/cli.cr
```

## Tests

```sh
crystal spec   # 83 examples, including dataset thresholds
```

## Integration testing (1-to-1 against MathJax)

1000 TeX formulas from English Wikipedia are run through `mathjax.cr` and
through real MathJax (`mathjax-full`); the MathML trees are compared after
normalization (see `test/datasets/REPORT.md`):

- **99.3%** of formulas parsed (993/1000);
- **99.1%** structurally identical trees (990/999 comparable).

```sh
crystal run tools/compare.cr        # full report + diffs.txt
crystal run tools/dump_one.cr -- 91 # ours vs ref trees for formula #91
```

The dataset and the reference are rebuildable: `tools/fetch_formulas.cr`
(Wikipedia API) and `tools/make_reference.js` (node + mathjax-full).

A golden SVG dataset (1000 formulas with expected output from the original
MathJax v3) lives in `dataset/` — see `dataset/README.md`.

## Layout

```
src/mathjax.cr                 public API
src/mathjax/tex/{parser,symbols}.cr     TeX input (input/tex port)
src/mathjax/asciimath/parser.cr         AsciiMath input
src/mathjax/mml/                         MML tree, serializer, MathML input
src/mathjax/html/renderer.cr            HTML output
src/mathjax/svg/renderer.cr             SVG output (metrics-based)
src/mathjax/fonts/tex_metrics.cr        TeX font glyph table (generated)
vendor/                                  MathJax sources (reference only)
```

## License

Apache-2.0 (as is MathJax itself). `mathjax.cr` is an independent Crystal
implementation; the font metrics are taken from MathJax data (Apache-2.0).
